import type { DesktopObservedState } from "../types";

export const CONNECTABLE_STATES = new Set<DesktopObservedState>(["READY", "CONNECTED"]);

export const TRANSITIONAL_STATES = new Set<DesktopObservedState>([
  "REQUESTED",
  "PROVISIONING",
  "BOOTING",
  "STOPPING",
  "TERMINATING",
]);

export function isConnectable(state: DesktopObservedState): boolean {
  return CONNECTABLE_STATES.has(state);
}

export function isTransitional(state: DesktopObservedState): boolean {
  return TRANSITIONAL_STATES.has(state);
}

export function stateLabel(state: DesktopObservedState): string {
  switch (state) {
    case "REQUESTED":
      return "Request received";
    case "PROVISIONING":
      return "Creating desktop";
    case "BOOTING":
      return "Starting Ubuntu";
    case "READY":
      return "Ready";
    case "CONNECTED":
      return "Connected";
    case "STOPPING":
      return "Stopping";
    case "STOPPED":
      return "Stopped";
    case "TERMINATING":
      return "Deleting";
    case "TERMINATED":
      return "Deleted";
    case "FAILED":
      return "Failed";
  }
}

export function stateTone(state: DesktopObservedState): "neutral" | "progress" | "success" | "warning" | "danger" {
  switch (state) {
    case "READY":
    case "CONNECTED":
      return "success";
    case "REQUESTED":
    case "PROVISIONING":
    case "BOOTING":
    case "STOPPING":
    case "TERMINATING":
      return "progress";
    case "STOPPED":
      return "warning";
    case "FAILED":
      return "danger";
    case "TERMINATED":
      return "neutral";
  }
}
