# Infrastructure & Stability Optimization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Improve device connection reliability and automate binary bundling.

**Architecture:** Enhance `DeviceManager` cleanup and integrate bundling scripts into Xcode.

**Tech Stack:** Swift, Bash, Xcode Build Phases.

---

### Task 1: Improve `DeviceManager` Lifecycle & Cleanup

**Files:**
- Modify: `flyflyfly/Services/Device/DeviceManager.swift`

- [ ] **Step 1: Implement robust process termination**

```swift
func terminateAllProcesses() {
    // Ensure all spawned processes (pymobiledevice3, dvt-location-stream) are killed
    // and pipes are closed.
}
```

- [ ] **Step 2: Add connection watchdog**

```swift
// Implement a timer that checks if the RSD tunnel is still alive
```

---

### Task 2: Integrate Bundling Scripts into Xcode

**Files:**
- Modify: `flyflyfly.xcodeproj/project.pbxproj` (via `update_pbxproj.py` if possible, or manual plan)

- [ ] **Step 1: Add "Run Script" Build Phase**

```bash
# Check if bundled/ exists, if not or if scripts changed, run them
if [ ! -d "bundled" ] || [ -f "scripts/build-bundled-pymobiledevice3.sh" ]; then
    bash scripts/build-bundled-pymobiledevice3.sh
fi
```
