# Sources for the separate wellness guidance

The wellness cards are simple, cited public-health guidance, not estimates from the mortality model.

- **Aerobic activity and sitting:** [CDC adult physical activity overview](https://www.cdc.gov/physical-activity-basics/guidelines/adults.html). Adults need at least 150 minutes of moderate-intensity activity, 75 minutes of vigorous-intensity activity, or an equivalent mix per week; move more and sit less. This package only tracks recreational minutes, so a card cannot certify that the person's **total** activity meets the guideline if work/transport activity is unknown.
- **Sleep:** [CDC About Sleep](https://www.cdc.gov/sleep/about/index.html). Ages 18–60: at least seven hours; 61–64: seven to nine; 65+: seven to eight. The model's `sleep_hours` is usual workday sleep, not sleep quality.
- **Smoking:** [CDC Cigarette Smoking](https://www.cdc.gov/tobacco/about/). Quitting benefits health at any age; cessation counseling and medication can help. No numeric survival gain is attributed to quitting by this package.
- **BMI:** [CDC About BMI](https://www.cdc.gov/bmi/about/). BMI is a screening measure and should be considered with other factors. The app should not treat the model's small inverse high-BMI association as an instruction to gain weight.

For the mortality artifact itself, see the [CDC linked mortality data page](https://www.cdc.gov/nchs/linked-data/mortality-files/index.html) and the [NHANES demographics codebook](https://wwwn.cdc.gov/Nchs/Data/Nhanes/Public/2007/DataFiles/DEMO_E.htm). These sources describe data provenance and the age-80 top code.
