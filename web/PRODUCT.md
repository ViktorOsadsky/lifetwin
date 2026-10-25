# Product

<!-- impeccable:product-schema 1 -->

Scope: the two web surfaces in `web/`. Product truth for the whole project lives in [MASTER_PLAN.md](../MASTER_PLAN.md) and wins over this file.

## Platform

web

## Stack

Static HTML, CSS and vanilla ES modules with inline SVG, no build step (user ruling 2026-10-24). A Flutter web build of the real app may later sit inside the booth demo as a secondary panel; the static side dominates. Hosting is undecided: everything must work from any static host, and nothing is deployed without the user's go-ahead. The booth demo calls the existing keyless FastAPI backend; its URL is configurable.

## Users

- **Landing page:** anyone who hears about LifeTwin (judges after the event, other hackers). Their job is to understand the idea in seconds and open the demo.
- **Booth demo:** hackathon judges walking past a laptop (mouse/trackpad and its keyboard, about 1440×900) at the Cal Hacks table, often while a teammate runs the phone demo. They watch a short guided run, then take over and type their own answers.

## Product Purpose

LifeTwin is a pet game about a digital twin of you. A mascot, Pip, chats with you about your health and habits, the twin lives in a little habitat that reflects your modeled outlook, and you try changes on the twin before choosing a real-world step. The web demo exists to show judges that the conversation really understands everyday wording, that every value is checked with you before it is kept, and that game health is separate from your health.

## Positioning

A health conversation that never accepts a value it did not hear and confirm, inside a game that keeps play, cosmetics, real inputs and experiments strictly apart.

## Operating Context

Loud, busy hackathon floor; judges have one to three minutes; venue wifi may fail. The demo follows a semi-set script but judges may try anything, so intake wording must be really live. A labeled offline replay must take over if the server cannot be reached.

## Capabilities and Constraints

- Real today (keyless backend): `/api/onboarding/turn` guided intake with confirmation and correction; `/api/quiz/questions` reviewed quiz bank; `/api/advisor` curated cited plans.
- Deferred: prediction. No survival number, curve or delta may be real. Outlook figures are visible placeholders labeled "Example numbers · linked, not proven".
- Voice runs on the phone app; the web demo is typing-first.
- Never an exact death date, countdown, or "risk/mortality/death/bad/warning" wording. Associations are never causes.
- Wrong quiz answers change only game health and the twin's mood.
- The twin's body stays a fixed default on the web (the data-driven body ruling still conflicts with AGENTS.md).
- Judges' typed text is processed and not stored; the booth says not to type real details.

## Brand Commitments

Name LifeTwin; mascot Pip (orb creature with a leaf sprout). Visual system pinned in `docs/design-brief.md` on branch `claude/design-handoff-mcp-setup-d0d680`: light blue/green tokens, Bricolage Grotesque display with DM Sans UI, habitat tiers Thriving/Good/Steady/Resting, seamless sky, few words for older adults, gentle tone.

## Evidence on Hand

PR #26 intake results (37% → 99.6% on the dev set, 92% held out, zero wrong values), the reviewed quiz bank in `server/lifetwin/quiz/content/questions.json`, curated advisor sources. No users, testimonials, press or model accuracy numbers exist; none may be invented.

## Product Principles

1. Show the real thing working; label every illustration as one.
2. Check before keeping: no value enters without confirmation.
3. Curiosity, never fear.
4. Few words, big type, one idea per view.
5. Survive a judge going off-script.

## Accessibility & Inclusion

Older adults are a primary audience of the product: large type, high contrast, plain words, keyboard operable, reduced motion respected, no meaning by colour alone.
