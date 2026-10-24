This is an important constraint, and it actually changes how I would approach LifeSim's machine learning.

**Every feature used by the core longevity model should be something a user can realistically provide.** That means through a questionnaire, conversation with an AI agent, smartphone, wearable, or inexpensive measurement device.

I would not train the main model on 50 laboratory biomarkers that most users cannot access.

However, I think we can do something more interesting: **build two prediction models and potentially a physical LifeSim device.**

# 1. Revised ML strategy: Three levels of data

I'd divide LifeSim into three levels.

| Level                  | Data source                              | User effort            | Purpose                        |
| ---------------------- | ---------------------------------------- | ---------------------- | ------------------------------ |
| **Level 1: Lifestyle** | AI conversation                          | 2–3 minutes            | Immediate longevity prediction |
| **Level 2: Health**    | Wearable, phone, home measurements       | 1–5 minutes            | More personalized prediction   |
| **Level 3: Clinical**  | Optional blood tests and medical records | Upload or manual entry | Advanced prediction            |

The key requirement is that **Level 1 works completely independently**.

Someone should be able to open LifeSim, answer a few questions, and receive their estimated survival curve.

Levels 2 and 3 provide additional information when available.

## Level 1: Data anyone can provide

These are the features I would prioritize for your main survival model.

| Feature                        | How the user provides it | NHANES source |
| ------------------------------ | ------------------------ | ------------- |
| Age                            | Self-report              | DEMO          |
| Sex                            | Self-report              | DEMO          |
| Height                         | Self-report              | BMX           |
| Weight                         | Self-report or scale     | BMX           |
| BMI                            | Automatically calculated | BMX           |
| Sleep duration                 | AI question              | SLQ           |
| Exercise frequency             | AI question              | PAQ           |
| Exercise duration              | AI question              | PAQ           |
| Smoking status                 | AI question              | SMQ           |
| Cigarettes per day             | AI question              | SMQ           |
| Alcohol consumption            | AI question              | ALQ           |
| Dietary habits                 | AI conversation          | DBQ           |
| General health                 | Self-assessment          | HSQ           |
| Diabetes diagnosis             | AI question              | DIQ           |
| Cardiovascular disease history | AI question              | MCQ           |
| Hypertension diagnosis         | AI question              | BPQ           |
| Weight history                 | AI question              | WHQ           |

All of these can be collected through an AI agent.

For example, instead of displaying 20 questionnaire fields, the agent could ask:

> "Walk me through a typical day. How much do you sleep, what do you usually eat, and how active are you?"

The AI extracts structured values and asks follow-up questions when necessary.

Importantly, the agent must not guess missing values.

For exercise, for instance, NHANES uses specific questions about activity type, frequency, and duration. Your conversational interface needs to convert the user's answers into equivalent measurements. ([CDC][1])

**This should be your primary model.**

---

# 2. Level 2: Data from wearables and inexpensive devices

This is where hardware becomes interesting.

| Measurement             | Collection method               | NHANES equivalent                     | Recommendation                  |
| ----------------------- | ------------------------------- | ------------------------------------- | ------------------------------- |
| Resting heart rate      | Smartwatch or heart-rate sensor | Limited comparability                 | Optional                        |
| Blood pressure          | Validated electronic cuff       | BPX                                   | Highly recommended              |
| Weight                  | Smart scale                     | BMX                                   | Useful                          |
| Sleep duration          | Smartwatch                      | SLQ                                   | Useful, but measurement differs |
| Daily activity          | Smartwatch or smartphone        | PAQ                                   | Useful, but measurement differs |
| Blood oxygen saturation | Pulse oximeter                  | No direct equivalent in selected data | Low priority                    |
| Heart-rate variability  | Compatible wearable             | Not consistently available            | Skip initially                  |
| Body temperature        | Digital sensor                  | Limited relevance to your model       | Skip                            |

One methodological issue: the model must be trained on measurements that are comparable to what the user provides.

For example, NHANES sleep duration is self-reported. A wearable's estimated sleep duration is measured differently.

Similarly, NHANES physical activity questionnaires aren't directly interchangeable with smartwatch step counts.

You can still integrate these devices, but you need a conversion or validation strategy.

---

# 3. Should you build a LifeSim device?

**For Cal Hacks, I'd consider it — but only if it contributes meaningful data to your prediction model.**

My preferred hardware concept would be:

## LifeSim Pulse — A Connected Health Scanner

Imagine a small physical device that sits on a table.

A user places their finger on a sensor.

The device measures their pulse and sends the result to the LifeSim dashboard.

The graph updates automatically.

### Potential hardware

| Component            | Purpose                              |
| -------------------- | ------------------------------------ |
| ESP32                | Microcontroller with Wi-Fi/Bluetooth |
| MAX30102             | Optical pulse sensor                 |
| Small OLED display   | Display heart rate                   |
| 3D-printed enclosure | Physical presentation                |
| USB power            | Power                                |

You could build something that looks visually impressive for a hackathon demonstration.

However, there is a limitation.

**Heart rate isn't currently one of the features we've selected for the NHANES mortality model.**

If you don't train on a comparable resting-heart-rate measurement, attaching a heart-rate sensor won't improve the prediction.

You could still display heart rate as a separate measurement, but you shouldn't imply it changed the modeled survival probability.

### My preferred alternative: Connected blood pressure

Blood pressure is already part of the LifeSim model specification.

A validated commercial upper-arm cuff could provide measurements that users can understand and enter into the app. The American Heart Association recommends validated, automatic upper-arm cuff monitors for home blood-pressure measurement. ([www.heart.org][2])

If you have access to a compatible Bluetooth-enabled cuff, you could integrate it into the app.

I would not attempt to invent a clinically accurate cuffless blood-pressure monitor during the hackathon.

---

# 4. The biggest ML change: Train separate models

Originally, we planned to download a large collection of clinical and laboratory data and train one model.

I would revise that.

### Model A: Lifestyle Survival Model

**Used by every LifeSim user.**

Inputs:

* Age
* Sex
* BMI
* Sleep
* Exercise
* Smoking
* Alcohol
* Dietary behaviors
* General health
* Existing health conditions

Output:

* Estimated survival probability over supported horizons.
* Comparison with alternative lifestyle profiles.

This should be your priority.

### Model B: Clinical Survival Model

**Used when additional measurements are available.**

Includes Model A's features plus:

* Blood pressure
* Total cholesterol
* HDL cholesterol
* HbA1c
* Kidney function
* Selected other biomarkers

Output:

A potentially more informative survival estimate.

This model can be trained on the additional NHANES examination and laboratory datasets you're already downloading.

One caution: Model B isn't automatically more accurate. You'll need to evaluate it on held-out data and determine whether its additional features actually improve performance.

### What if users don't know their clinical measurements?

Do not invent values.

Either use Model A or explicitly handle missing measurements in a separately validated model.

---

# 5. One feature that could make LifeSim stand out

## AI-Assisted Health Onboarding

Instead of making users fill out forms, let them talk to LifeSim.

For example:

**LifeSim:** "Tell me about your typical week."

**User:** "I'm a college student. I sleep around six hours, go to the gym twice a week, and eat dining hall food."

**LifeSim:** "About how long are your gym sessions?"

**User:** "An hour each."

**LifeSim:** "Do you smoke or vape?"

**User:** "No."

The agent extracts:

```json
{
  "sleep_hours": 6,
  "exercise_sessions_weekly": 2,
  "exercise_minutes_weekly": 120,
  "smoking_status": "never"
}
```

The agent then verifies the extracted values before sending them to the ML model.

A structured profile could also contain provenance:

```json
{
  "sleep_hours": {
    "value": 6,
    "source": "self_report",
    "confirmed": true
  }
}
```

This becomes especially valuable when combining self-reported information with wearable measurements.

**One detail:** The agent should distinguish cigarette smoking from vaping. Those aren't interchangeable exposures, and your training dataset needs to support whichever feature you use.

---

# 6. How this changes the downloader

Your existing downloader doesn't need to remove the laboratory files.

Those can support the optional Clinical Survival Model.

However, I would prioritize these modules:

| Category      | Modules                 | Priority  |
| ------------- | ----------------------- | --------- |
| Demographics  | DEMO                    | Essential |
| Examination   | BMX                     | Essential |
| Questionnaire | SLQ, PAQ, SMQ, ALQ      | Essential |
| Questionnaire | DIQ, DBQ, MCQ, HSQ      | Essential |
| Questionnaire | BPQ, WHQ                | High      |
| Examination   | BPX                     | High      |
| Dietary       | DR1TOT                  | Optional  |
| Laboratory    | TCHOL, HDL, GHB, BIOPRO | Optional  |
| Questionnaire | CDQ, DPQ                | Optional  |
| Mortality     | Linked mortality files  | Essential |

**I would keep the downloads but change the feature-engineering pipeline so the core model never requires blood tests.**

Also, I'd reconsider `DR1TOT` for the main model.

It contains quantitative nutrient intake from a 24-hour dietary recall. Most users won't know their exact daily sodium, protein, saturated fat, and fiber consumption.

You could ask the AI agent to reconstruct these estimates from meals, but that introduces considerable uncertainty.

For the MVP, I would rely on simpler dietary questions that map to actual NHANES variables. If those variables are inconsistent across cycles, omit them rather than invent a diet-quality score.

---

# 7. An important limitation: Your users may be too young

This is especially relevant at Cal Hacks.

Most people testing your app will probably be college students.

A mortality model trained on NHANES will generally be much better informed about short-term mortality among older adults than about the lifetime outcomes of healthy 18–22-year-olds.

For a healthy 19-year-old, the predicted 10-year survival probability may be extremely high regardless of whether they sleep six or eight hours.

That creates a product problem: **the graph may barely move during your demo.**

You shouldn't solve that by exaggerating risk changes.

Instead, consider displaying a second visualization showing relative risk or comparing statistically supported risk profiles. You can also present established long-term health recommendations independently of the model.

This is another reason not to promise exact dates of death.

---

# 8. My recommendation for Cal Hacks

Given that you have hardware available, I'd prioritize the project like this:

| Component                                   | Priority |
| ------------------------------------------- | -------- |
| Actual NHANES survival model                | 10/10    |
| AI conversational onboarding                | 10/10    |
| Interactive survival simulation             | 10/10    |
| Scenario comparison                         | 10/10    |
| Validated blood-pressure device integration | 7/10     |
| Custom pulse sensor                         | 5/10     |
| Laboratory-data model                       | 5/10     |
| Custom clinical hardware                    | 2/10     |

A physical device could make the demonstration more memorable, but **I wouldn't let hardware compromise the predictive model or frontend.**

The strongest version of LifeSim for this weekend is:

**A user talks to an AI about their life, receives a data-driven survival estimate, and can interactively explore how alternative lifestyle profiles compare.**

If you have a functioning hardware integration as well, that's a bonus.

The most important architectural principle is:

**No model input should be required unless LifeSim can explain exactly how an ordinary user can obtain it.** Optional clinical measurements are fine, but every user must be able to complete the basic experience without them.

[1]: https://wwwn.cdc.gov/Nchs/Data/Nhanes/Public/2017/DataFiles/PAQ_J.htm?utm_source=chatgpt.com "PAQ_J"
[2]: https://www.heart.org/en/health-topics/high-blood-pressure/understanding-blood-pressure-readings/monitoring-your-blood-pressure-at-home?utm_source=chatgpt.com "Home Blood Pressure Monitoring | American Heart Association"
