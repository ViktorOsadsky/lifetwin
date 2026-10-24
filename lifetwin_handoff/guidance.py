"""Source-backed wellness cards. These never use survival-model coefficient signs."""

CDC_ACTIVITY = 'https://www.cdc.gov/physical-activity-basics/guidelines/adults.html'
CDC_SLEEP = 'https://www.cdc.gov/sleep/about/index.html'
CDC_SMOKING = 'https://www.cdc.gov/tobacco/about/'
CDC_BMI = 'https://www.cdc.gov/bmi/about/'


def _card(card_id, level, title, message, source):
    return {'id': card_id, 'level': level, 'title': title, 'message': message,
            'source_url': source, 'derived_from_survival_model': False}


def guidance(profile: dict, context: dict | None = None):
    age = profile.get('age')
    if not isinstance(age, (int, float)) or age < 18:
        return [_card('adult_guidance_scope', 'info', 'Adult guidance unavailable',
                      'The bundled wellness rules are for adults; use age-appropriate guidance instead.', CDC_ACTIVITY)]
    cards = []
    smoking = profile.get('smoking_status')
    if smoking == 2:
        cards.append(_card('smoking', 'opportunity', 'Smoking',
                           'Quitting cigarettes benefits health at any age. Consider evidence-based quit support.', CDC_SMOKING))
    elif smoking in (0, 1):
        cards.append(_card('smoking', 'strength', 'Not currently smoking',
                           'You report that you do not currently smoke cigarettes.', CDC_SMOKING))
    moderate = profile.get('moderate_recreation_min_week')
    vigorous = profile.get('vigorous_recreation_min_week')
    if isinstance(moderate, (int, float)) and isinstance(vigorous, (int, float)):
        equivalent = moderate + 2 * vigorous
        if equivalent >= 150:
            cards.append(_card('activity', 'strength', 'Recreational activity',
                               'Your logged moderate and vigorous recreation meets the adult aerobic activity minimum of 150 moderate-equivalent minutes per week. Other activity and strength training are not captured here.', CDC_ACTIVITY))
        else:
            cards.append(_card('activity', 'opportunity', 'Recreational activity',
                               f'Your logged recreation is about {equivalent:.0f} moderate-equivalent minutes per week. Adults are advised to aim for at least 150; work and transport activity are not captured here.', CDC_ACTIVITY))
    sleep = profile.get('sleep_hours')
    if isinstance(sleep, (int, float)):
        minimum = 7
        maximum = 8 if age >= 65 else 9 if age >= 61 else None
        if sleep < minimum:
            cards.append(_card('sleep', 'opportunity', 'Sleep',
                               f'Your usual workday sleep is {sleep:.1f} hours. CDC recommends at least seven hours for adults.', CDC_SLEEP))
        elif maximum is not None and sleep > maximum:
            cards.append(_card('sleep', 'info', 'Sleep pattern',
                               f'Your usual workday sleep is {sleep:.1f} hours; CDC lists {minimum}–{maximum} hours for your age group. Persistent changes in sleep can be discussed with a clinician.', CDC_SLEEP))
        else:
            cards.append(_card('sleep', 'strength', 'Sleep duration',
                               'Your usual workday sleep meets the CDC duration recommendation for your age group. Sleep quality is not measured here.', CDC_SLEEP))
    if context and context.get('complete_weeks', 0) >= 2:
        change = context['sitting_last_week'] - context['sitting_first_week']
        if change <= -60:
            cards.append(_card('sitting_trend', 'strength', 'Less sitting',
                               'Your logged awake sitting time decreased by at least an hour per day from the first to the latest week.', CDC_ACTIVITY))
        elif change >= 60:
            cards.append(_card('sitting_trend', 'opportunity', 'More sitting',
                               'Your logged awake sitting time increased by at least an hour per day from the first to the latest week. Moving more and sitting less is generally recommended.', CDC_ACTIVITY))
    if not any(card['id'] == 'sitting_trend' for card in cards) and profile.get('sedentary_min_day') is not None:
        cards.append(_card('sitting', 'info', 'Awake sitting',
                           'Your reported sitting time is tracked. Current adult guidance is to move more and sit less; this package does not impose a single daily cutoff.', CDC_ACTIVITY))
    if profile.get('bmi') is not None:
        cards.append(_card('bmi', 'info', 'BMI context',
                           'BMI is a screening measure, not a diagnosis or an instruction to gain or lose weight. Consider it alongside other health information.', CDC_BMI))
    return cards
