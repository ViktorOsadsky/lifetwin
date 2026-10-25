#pragma once
// BLE GATT service (HW-07). Requires NimBLE-Arduino >= 2.0.
// UUIDs below are PLACEHOLDERS: the repo has no band-protocol contract yet.
// Agree on them with the Flutter owner (APP-01) before the app depends on them.
#include <NimBLEDevice.h>
#include <string>
#include "minute.h"

#define LT_SVC_UUID     "4c540001-7b2a-4f0e-9a51-0d1e2c3b4a50"
#define LT_INFO_UUID    "4c540002-7b2a-4f0e-9a51-0d1e2c3b4a50"  // READ
#define LT_TIME_UUID    "4c540003-7b2a-4f0e-9a51-0d1e2c3b4a50"  // WRITE  uint32 LE unix seconds
#define LT_CTRL_UUID    "4c540004-7b2a-4f0e-9a51-0d1e2c3b4a50"  // WRITE  see README
#define LT_HISTORY_UUID "4c540005-7b2a-4f0e-9a51-0d1e2c3b4a50"  // NOTIFY 12-byte MinuteRecord
#define LT_TOTALS_UUID  "4c540007-7b2a-4f0e-9a51-0d1e2c3b4a50"  // READ+NOTIFY 20 bytes: sit s u32, stand s u32, other s u32, steps u32, run s u16, posture u8, 0
#define LT_SUMMARY_UUID "4c540008-7b2a-4f0e-9a51-0d1e2c3b4a50"  // READ: headline day summary (JSON text, <= 512 bytes). NOTIFY: the full JSON file, sent in chunks after CTRL 0x0B
#define LT_LIVE_UUID    "4c540006-7b2a-4f0e-9a51-0d1e2c3b4a50"  // NOTIFY 5 bytes: enmo_mg u16, steps_this_min u16, posture u8 

class BandBle;
static BandBle* gBle = nullptr;

class BandBle {
 public:
  volatile bool connected = false;
  volatile bool timePending = false;
  uint8_t timeBuf[32]; volatile uint8_t timeLen = 0;   // raw bytes written to the time characteristic (4 = unix, 6 = unix + zone, or typed text)
  volatile bool saveRequested = false, sendFileRequested = false;   // CTRL 0x0A / 0x0B
  volatile bool indexRequested = false, dayFileRequested = false, ackDayRequested = false;   // CTRL 0x0D / 0x0C / 0x0E
  char ctrlArg[17]; volatile uint8_t ctrlArgLen = 0;                 // text argument that follows 0x0C / 0x0E (a date YYYY-MM-DD)
  volatile uint16_t mtu = 23;                                        // negotiated size, used to pick the chunk size
  volatile bool streamPending = false; volatile uint32_t streamSince = 0;
  volatile bool stopPending = false;
  volatile bool liveOn = false;
  volatile bool resetTotals = false;
  volatile bool stepSettingsPending = false; volatile uint8_t stepSettingsValue = 0;   // CTRL 0x09 + byte
  uint8_t stepSettings = 0;                         // current settings byte, reported in INFO byte 9                // set by CTRL 0x07
  uint32_t totSit = 0, totStand = 0, totOther = 0, totSteps = 0;   // set by the main loop, sent at 1 Hz
  uint16_t totRun = 0; uint8_t totPosture = 0;
  volatile bool liveDirty = false;                  // set when posture changes: notify immediately
  volatile bool capStand = false, capSit = false;   // set by CTRL 0x05 / 0x06
  uint16_t liveEnmoMg = 0, liveSteps = 0;     // set by the main loop
  uint8_t livePosture = 0, postureState = 0;  // postureState bits: 1 stand captured, 2 sit captured, 4 both valid

  void begin(RingBuffer* ring) {
    ring_ = ring; gBle = this;
    NimBLEDevice::init("LifeTwin Band");
    server_ = NimBLEDevice::createServer();
    server_->setCallbacks(new ServerCb());
    NimBLEService* svc = server_->createService(LT_SVC_UUID);
    info_ = svc->createCharacteristic(LT_INFO_UUID, NIMBLE_PROPERTY::READ);
    NimBLECharacteristic* t = svc->createCharacteristic(LT_TIME_UUID, NIMBLE_PROPERTY::WRITE);
    NimBLECharacteristic* c = svc->createCharacteristic(LT_CTRL_UUID, NIMBLE_PROPERTY::WRITE);
    t->setCallbacks(new TimeCb());
    c->setCallbacks(new CtrlCb());
    hist_ = svc->createCharacteristic(LT_HISTORY_UUID, NIMBLE_PROPERTY::NOTIFY);
    live_ = svc->createCharacteristic(LT_LIVE_UUID, NIMBLE_PROPERTY::NOTIFY);
    tot_ = svc->createCharacteristic(LT_TOTALS_UUID, NIMBLE_PROPERTY::READ | NIMBLE_PROPERTY::NOTIFY);
    sum_ = svc->createCharacteristic(LT_SUMMARY_UUID, NIMBLE_PROPERTY::READ | NIMBLE_PROPERTY::NOTIFY);
    { const char* none = "{\"headline_only\":true,\"note\":\"no summary yet: set the time, then write 0A to the control characteristic\"}"; sum_->setValue((const uint8_t*)none, strlen(none)); }
    { uint8_t z[20] = {0}; tot_->setValue(z, sizeof z); }
    svc->start();
    updateInfo();
    // The 128-bit service UUID + flags + the name do not fit in one 31-byte advertising
    // packet, so the name was being dropped (scanners showed "N/A"). Put the UUID in the
    // advertisement and the name in the scan response.
    NimBLEAdvertising* adv = NimBLEDevice::getAdvertising();
    NimBLEAdvertisementData advData;
    advData.setFlags(BLE_HS_ADV_F_DISC_GEN | BLE_HS_ADV_F_BREDR_UNSUP);
    advData.addServiceUUID(LT_SVC_UUID);
    NimBLEAdvertisementData scanData;
    scanData.setName("LifeTwin Band");
    adv->setAdvertisementData(advData);
    adv->setScanResponseData(scanData);
    adv->enableScanResponse(true);
    adv->start();
  }

  // INFO: [fw_major, fw_minor, format_version, record_size, capacity u16, stored u16, posture_state, step_settings]
  void updateInfo() {
    uint8_t b[10] = {FW_MAJOR, FW_MINOR, FORMAT_VERSION, sizeof(MinuteRecord),
                     (uint8_t)(RING_MINUTES & 0xFF), (uint8_t)(RING_MINUTES >> 8),
                     (uint8_t)(ring_->size() & 0xFF), (uint8_t)(ring_->size() >> 8), postureState, stepSettings};
    info_->setValue(b, sizeof b);
  }

  // The headline summary: what a plain READ of the summary characteristic returns.
  void setHeadline(const char* json, size_t len) { if (len > 512) len = 512; sum_->setValue((const uint8_t*)json, len); }
  // Send a whole text file as notifications on the summary characteristic (the phone must have notifications switched on).
  void startFileStream(const char* data, size_t len) { fileData_.assign(data, len); filePos_ = 0; fileFails_ = 0; fileEofSent_ = false; fileStreaming_ = true; }
  bool fileStreamBusy() const { return fileStreaming_; }

  // Call every loop iteration with millis().
  void service(uint32_t now) {
    if (!connected) { streaming_ = false; fileStreaming_ = false; return; }
    if (fileStreaming_ && now - lastFileChunk_ >= 25) {
      lastFileChunk_ = now;
      size_t chunk = mtu > 23 ? (size_t)mtu - 3 : 20; if (chunk > 180) chunk = 180;
      if (filePos_ < fileData_.size()) {
        size_t n = fileData_.size() - filePos_; if (n > chunk) n = chunk;
        if (sum_->notify((const uint8_t*)fileData_.data() + filePos_, n)) { filePos_ += n; fileFails_ = 0; }
        else if (++fileFails_ > 80) fileStreaming_ = false;          // nobody listening: give up after about 2 s
      } else if (!fileEofSent_) {
        const char* eof = "<EOF>"; if (sum_->notify((const uint8_t*)eof, 5)) { fileEofSent_ = true; fileStreaming_ = false; }
        else if (++fileFails_ > 80) fileStreaming_ = false;
      }
    }
    if (stopPending) { stopPending = false; streaming_ = false; }
    if (streamPending) { streamPending = false; cursor_ = streamSince; streaming_ = true; }

    if (streaming_ && now - lastSend_ >= 15) {       // ~66 records/s
      lastSend_ = now;
      const MinuteRecord* next = nullptr;
      for (uint16_t i = 0; i < ring_->size(); i++) {
        if (ring_->at(i).ts > cursor_) { next = &ring_->at(i); break; }
      }
      if (!next) {                                    // end marker: ts = 0xFFFFFFFF
        uint8_t end[sizeof(MinuteRecord)]; memset(end, 0xFF, sizeof end);
        if (hist_->notify(end, sizeof end)) streaming_ = false;
      } else if (hist_->notify((const uint8_t*)next, sizeof(MinuteRecord))) {
        cursor_ = next->ts;                           // only advance when the send was accepted
      }
    }
    if (liveOn && (liveDirty || now - lastLive_ >= 1000)) {
      lastLive_ = now;
      liveDirty = false;
      uint8_t b[5] = {(uint8_t)(liveEnmoMg & 0xFF), (uint8_t)(liveEnmoMg >> 8),
                      (uint8_t)(liveSteps & 0xFF), (uint8_t)(liveSteps >> 8), livePosture};
      live_->notify(b, sizeof b);
    }
    if (liveOn && now - lastTot_ >= 1000) {
      lastTot_ = now;
      uint8_t b[20];
      put32(b, 0, totSit); put32(b, 4, totStand); put32(b, 8, totOther); put32(b, 12, totSteps);
      b[16] = (uint8_t)(totRun & 0xFF); b[17] = (uint8_t)(totRun >> 8); b[18] = totPosture; b[19] = 0;
      tot_->setValue(b, sizeof b);
      tot_->notify(b, sizeof b);
    }
  }

 private:
  struct ServerCb : public NimBLEServerCallbacks {
    void onConnect(NimBLEServer*, NimBLEConnInfo&) override { gBle->connected = true; }
    void onMTUChange(uint16_t MTU, NimBLEConnInfo&) override { gBle->mtu = MTU; }
    void onDisconnect(NimBLEServer*, NimBLEConnInfo&, int) override {
      gBle->connected = false; gBle->mtu = 23;
      NimBLEDevice::getAdvertising()->start();        // keep advertising so it can reconnect
    }
  };
  struct TimeCb : public NimBLECharacteristicCallbacks {
    void onWrite(NimBLECharacteristic* c, NimBLEConnInfo&) override {
      NimBLEAttValue v = c->getValue();
      size_t n = v.length(); if (n > 31) n = 31;
      if (n >= 4) { memcpy(gBle->timeBuf, v.data(), n); gBle->timeLen = (uint8_t)n; gBle->timePending = true; }
    }
  };
  // CTRL: 0x01 + u32 LE since_ts -> stream records with ts > since_ts
  //       0x02 -> stop;  0x03 -> live on;  0x04 -> live off
  //       0x05 -> capture STANDING reference (5 s delay, then 3 s hold still)
  //       0x06 -> capture SITTING reference  (same)
  //       0x07 -> reset the live sit / stand / steps timers
  //       0x0A -> build the day summary now, save it as a JSON file in the band's flash, update the headline read
  //       0x0B -> same, then send the full JSON file as notifications on the summary characteristic (switch them on first)
  //       0x0C + "YYYY-MM-DD" -> send that saved day's JSON file as notifications (switch them on first)
  //       0x0D -> send the list of saved days as notifications
  //       0x0E + "YYYY-MM-DD" -> delete that day's file (only days before today), once the app has stored it
  //       0x09 + byte -> step settings: bits 0-2 sensitivity 1..5, bit 3 ignore-steps-while-sitting, bit 4 count-each-step-twice
  struct CtrlCb : public NimBLECharacteristicCallbacks {
    void onWrite(NimBLECharacteristic* c, NimBLEConnInfo&) override {
      NimBLEAttValue v = c->getValue();
      if (v.length() < 1) return;
      const uint8_t* d = v.data();
      switch (d[0]) {
        case 0x01:
          if (v.length() >= 5) {
            gBle->streamSince = (uint32_t)d[1] | ((uint32_t)d[2] << 8) | ((uint32_t)d[3] << 16) | ((uint32_t)d[4] << 24);
            gBle->streamPending = true;
          }
          break;
        case 0x02: gBle->stopPending = true; break;
        case 0x03: gBle->liveOn = true; break;
        case 0x04: gBle->liveOn = false; break;
        case 0x05: gBle->capStand = true; break;
        case 0x06: gBle->capSit = true; break;
        case 0x07: gBle->resetTotals = true; break;
        case 0x0A: gBle->saveRequested = true; break;       // build today's summary and save it as a JSON file on the band
        case 0x0B: gBle->sendFileRequested = true; break;   // ...and send the full file as notifications
        case 0x0C: case 0x0E: {                              // + date "YYYY-MM-DD": send that day's saved file / delete it after the app has stored it
          size_t n = v.length() > 1 ? v.length() - 1 : 0; if (n > 16) n = 16;
          memcpy(gBle->ctrlArg, d + 1, n); gBle->ctrlArg[n] = 0; gBle->ctrlArgLen = (uint8_t)n;
          if (d[0] == 0x0C) gBle->dayFileRequested = true; else gBle->ackDayRequested = true;
          break; }
        case 0x0D: gBle->indexRequested = true; break;       // send the list of saved days
        case 0x09:
          if (v.length() >= 2) { gBle->stepSettingsValue = d[1]; gBle->stepSettingsPending = true; }
          break;
      }
    }
  };

  static void put32(uint8_t* b, int o, uint32_t v) { b[o] = v & 0xFF; b[o + 1] = (v >> 8) & 0xFF; b[o + 2] = (v >> 16) & 0xFF; b[o + 3] = (v >> 24) & 0xFF; }
  RingBuffer* ring_ = nullptr;
  NimBLEServer* server_ = nullptr;
  NimBLECharacteristic *info_ = nullptr, *hist_ = nullptr, *live_ = nullptr, *tot_ = nullptr, *sum_ = nullptr;
  bool streaming_ = false;
  std::string fileData_; size_t filePos_ = 0; int fileFails_ = 0; bool fileStreaming_ = false, fileEofSent_ = false; uint32_t lastFileChunk_ = 0;
  uint32_t cursor_ = 0, lastSend_ = 0, lastLive_ = 0, lastTot_ = 0;
};
