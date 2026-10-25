// Compare step detectors on the scenarios.  g++ -std=c++17 -O1 -I../lifetwin_band step_compare.cpp -o step_compare
#include <cstdio>
#include <map>
#include "step_scenarios.h"
#include "steps_old.h"
#ifdef NEW
#include "steps.h"
#endif

template <class D, class F> int run(const Scenario& s, F gateFn) {
  D d; int total = 0; for (size_t i = 0; i < s.mag.size(); i++) total += gateFn(d, s.mag[i], (uint32_t)(i * 20), s);
  return total;
}
#ifdef SCORE
static float mape(std::vector<float>& v, int truth) { float s = 0; for (float x : v) s += fabsf(x - truth) / truth; return 100 * s / v.size(); }
#endif
int main() {
#ifdef FAMILY
  gFamily = FAMILY;
#endif
  const int SEEDS = 12; std::map<std::string, std::vector<float>> oldErr, newErr, oldC, newC;
  std::vector<std::string> order; std::map<std::string, int> truth;
  for (unsigned seed = 1; seed <= SEEDS; seed++) for (auto& s : makeScenarios(seed)) {
    if (seed == 1) order.push_back(s.name);
    truth[s.name] = s.truth;
    int o = run<OldStepDetector>(s, [](OldStepDetector& d, float m, uint32_t t, const Scenario&) { return (int)d.update(m, t); });
    oldC[s.name].push_back(o);
#ifdef NEW
    int n = run<StepDetector>(s, [](StepDetector& d, float m, uint32_t t, const Scenario& sc) { return (int)d.update(m, t, !sc.seated); });
    newC[s.name].push_back(n);
#endif
  }
#ifdef SCORE
  { float walk = 0, small = 0, shortb = 0, seatedFalse = 0; int nw = 0;
    for (auto& name : order) { int t = truth[name]; if (t == 0) { for (float x : newC[name]) seatedFalse += x; continue; }
      float e = mape(newC[name], t); if (name.find("small") != std::string::npos || name.find("SMALL") != std::string::npos) small += e;
      else if (name.find("room") != std::string::npos || name.find("start") != std::string::npos || name.find("mixed") != std::string::npos) shortb += e; else { walk += e; nw++; } }
    printf("fam %d  normal/slow/fast/weak-leg err %5.1f%%  small steps err %5.1f%%  stop-start/short err %5.1f%%  false steps seated %.0f\n", gFamily, walk / nw, small / 2, shortb / 3, seatedFalse); return 0; }
#endif
  printf("%-46s %5s | %-17s", "scenario (12 random runs each)", "truth", "OLD mean (range)");
#ifdef NEW
  printf(" | %-17s", "NEW mean (range)");
#endif
  printf("\n");
  for (auto& name : order) {
    auto stat = [&](std::vector<float>& v, char* buf) { float mn = 1e9, mx = -1e9, sum = 0; for (float x : v) { mn = fminf(mn, x); mx = fmaxf(mx, x); sum += x; } sprintf(buf, "%5.1f (%d-%d)", sum / v.size(), (int)mn, (int)mx); };
    char a[48], b[48] = ""; stat(oldC[name], a);
#ifdef NEW
    stat(newC[name], b);
#endif
    printf("%-46s %5d | %-17s | %-17s\n", name.c_str(), truth[name], a, b);
  }
}
