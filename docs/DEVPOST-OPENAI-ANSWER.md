We turned an AirPod into a Wii-style motion controller and used the resulting arcade to explore how AI can act inside a physical game.

WHY OPENAI: We wanted to investigate both tactical decision-making and computer use. Astra's Responses API lets a model choose an inspectable action that changes the rally. Codex helped us engineer and test the native system, then became part of a separate experiment operating the game's visible rival controls. Our development assistant also became a participant in the world it helped us build.

API INTEGRATION: In the integrated judging build, GPT-6 Astra receives game state and five legal shots through our local Node station. Strict structured output selects a candidate ID; that choice determines the return's target, flight duration, delay, and stroke. Swift handles movement and contact asynchronously from inference. The UI distinguishes the latest response from the actual applied shot and shows request timing, decision IDs, and cached reuse. API keys stay on the station.

CODEX DEVELOPMENT: We used parallel Codex agents and computer-use verification for the API adapter, shared provider contract, sensor inspector, decision provenance, and tests. Codex helped diagnose seven apparent rate limits as our own scheduler waking early, fixed the clock checks, and added an early-wake regression. It also helped fix a UI freeze caused by synchronous configuration reads. The station suite passed 25/25 tests; native lifecycle and collision checks also passed.

EVIDENCE: A corrected live comparison gave Astra and Jev identical twenty-state fixtures twice each. Both returned 40/40 legal decisions before a six-second deadline; median request time was 1,836.5 ms for Astra and 322 ms for Jev. This measures decision delivery, not tennis skill. Real API-selected returns were also verified through native collision code with explicitly simulated controller input.

Our desktop computer-use experiment is separate: slower incoming play, buffered swings, unranked, and operated through the visible game window. The tactical Astra opponent establishes the game's actual OpenAI API integration.
