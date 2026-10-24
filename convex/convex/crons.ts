import { cronJobs } from "convex/server";
import { internal } from "./_generated/api";

const crons = cronJobs();
// Backstop: each session already has a deletion scheduled at its expiry.
crons.interval("sweep expired sessions", { minutes: 5 }, internal.sessions.sweep, {});
export default crons;
