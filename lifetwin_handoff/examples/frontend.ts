// Call through your own authenticated backend proxy. The inference service itself stores no profile.
type SurvivalResult = {
  status: "available" | "missing_inputs" | "unsupported_age" | "unsupported_profile";
  survival_percent_by_year: Record<string, number> | null;
  message?: string;
};

type WellnessCard = {
  id: string;
  level: "strength" | "opportunity" | "info";
  title: string;
  message: string;
  source_url: string;
};

type TwinAssessment = {
  survival: SurvivalResult;
  wellness_cards: WellnessCard[];
  avatar: {
    survival_display: "annual_curve" | "unavailable";
    wellness_state: "steady" | "explore_changes" | "needs_input";
    strengths: string[];
    opportunities: string[];
  };
};

export async function assessTwin(request: unknown): Promise<TwinAssessment> {
  const response = await fetch("/api/lifetwin/v1/twin/assess", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(request),
  });
  const body = await response.json();
  if (!response.ok) throw new Error(body.detail ?? "LifeTwin assessment failed");
  return body as TwinAssessment;
}

export function avatarView(result: TwinAssessment) {
  const survival = result.survival;
  const points = survival.status === "available" && survival.survival_percent_by_year
    ? Object.entries(survival.survival_percent_by_year).map(([year, percent]) => ({
        year: Number(year), percent,
      }))
    : [];
  return {
    chartTitle: "Modeled survival of similar people",
    chartPoints: points, // cumulative survival at the end of years 1–5
    unavailableMessage: points.length ? null : survival.message ?? "Annual estimate unavailable",
    avatarState: result.avatar.wellness_state,
    strengths: result.wellness_cards.filter(card => card.level === "strength"),
    opportunities: result.wellness_cards.filter(card => card.level === "opportunity"),
    context: result.wellness_cards.filter(card => card.level === "info"),
  };
}
