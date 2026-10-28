# Tasks

## 1. Back in the guide

- [x] 1.1 `GuideScreen`: `.onExitCommand` on the grid: a paged window returns to `defaultStart()`, the current window focuses the rail (design 1).

## 2. Verification

- [x] 2.1 `LiveAndGuideUITests` reach the rail with Down, Back; new UI test on the demo server (archive channels 101–103): Left until a show begun four hours ago has focus, Back shows the current window with focus in row 101 (judged by the focused show's start), Back again focuses the rail; screenshots.
- [x] 2.2 `LiveAndGuideUITests`, `GuideUITests`, `GuideFocusUITests`, `ArchiveUITests` and the full Apple TV UI suite green.
- [ ] 2.3 Real Apple TV, Release build: the user reaches the rail with Back in their provider's guide.
