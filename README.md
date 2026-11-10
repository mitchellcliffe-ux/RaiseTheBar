# Raise The Bar Run (iPhone, subscription version)

A native iPhone app in SwiftUI. It builds a 12 week running plan from one recent race or time trial, adjusts paces from the effort ratings logged after each run, and is sold as a subscription with a free trial through Apple's in-app purchase.

## Read this first

- **None of this has been compiled.** There was no Swift toolchain where it was written. The new subscription code and the screen changes were proofread and bracket-checked only. Expect some compile errors on the first build. The build service below lists them for you; send them back and they are normally quick to fix.
- **You do not need a Mac to get it compiling.** `project.yml` and `.github/workflows/build.yml` let GitHub build and test it on one of their Macs. You do still need the paid Apple Developer Program to release it.
- **Three things in the code are placeholders** and must be changed before release: the bundle ID in `project.yml` (`com.CHANGEME...`), the privacy policy address in `Services/SubscriptionStore.swift`, and, if you pick different ones, the two subscription Product IDs in the same file.
- **The evidence notes and citations in the session library were written from memory.** Check each against the original paper before anyone else sees the app. They are in `Engine/SessionLibrary.swift`.
- **There is no app icon yet.** The App Store will not accept a build without one.
- Pace alerts on the Apple Watch are still not included (time goals only). See the comment in `Services/WatchExport.swift`.

## What changed in this version

**Subscription**
- `Services/SubscriptionStore.swift` loads the monthly and yearly subscriptions, sells them, restores them and keeps track of access. It uses Apple's StoreKit 2, so Apple takes the payment and handles the trial, renewals, refunds and cancelling. There is no account system and no server to run.
- `Views/PaywallView.swift` is the one screen people see when they are not subscribed. It shows the two options with Apple's own prices, the trial terms, Restore, and the Terms and Privacy links Apple asks for.
- The order is: setup, then the paywall, then the app. A new runner enters their details and has the plan built before being asked to start the trial. If a subscription ends, the paywall comes back and the plan and log stay on the phone.
- The free trial is Apple's introductory offer. People start it by subscribing, Apple reminds them before it ends, and Apple decides who is eligible (once per person). You set its length (7 days) in App Store Connect, not in the code.
- The Me tab has a Subscription section with the current period end, Manage or cancel, and Restore purchases.
- Test builds show a "Carry on without subscribing" button on the paywall so the app can be looked at before the products exist. It is compiled out of release builds.

**Simpler interface**
- Three tabs instead of five: Plan, Progress, Me.
- Plan opens with a Today section, so today's run is one tap away.
- The coach summary ("What your ratings say") moved into Progress. The session library moved into the Plan menu and the Me tab.
- First-launch setup asks only for what the plan needs. Weight, height, heart rate and fuelling are on Me > My details for later.
- Me is shorter: paces, My details, Session library, Apple Health, Subscription, Start again, About.

The plan engine, pace maths, adaptation and tests are unchanged.

## Getting it to compile without a Mac

1. Make a free GitHub account and create a new repository. A public repository gets free Mac build time. A private one is charged for it or uses up the free allowance quickly, so check GitHub's current pricing first.
2. Upload everything in this folder, including the hidden `.github` folder. On a phone the GitHub website's "Add file > Upload files" does not show hidden folders well, so this step is easier from a computer.
3. Open the Actions tab. The "Build and test" run starts by itself. It takes roughly 5 to 15 minutes.
4. Open the run. The summary page lists any compile errors and test failures. Copy that list back to me.

That gets the code correct. It does not sign or release anything.

## Getting it to TestFlight and the App Store

1. Join the Apple Developer Program (a yearly fee; Apple shows the UK price when you enrol). You can enrol from the Apple Developer app on an iPhone.
2. In the developer account, register a bundle ID with HealthKit ticked, and put the same ID in `project.yml`.
3. In App Store Connect, create the app, then under Subscriptions create one subscription group with two auto-renewable subscriptions whose Product IDs are `raisethebar.sub.yearly` and `raisethebar.sub.monthly`. Set your prices there, and add an introductory offer of "Free, 1 week" to each. Fill in the Paid Apps agreement, bank and tax details, or the products will not load.
4. Host a privacy policy at a public address and put that address in `SubscriptionStore.swift`.
5. Signing and uploading needs a Mac somewhere. Without your own, the usual routes are a second GitHub workflow that signs with an App Store Connect API key, or a hosted build service such as Codemagic. **That step is not in this folder yet.** It needs your Apple account details to set up, so it is the next job once the build is green.
6. Test through TestFlight on your own phone. Subscriptions bought in TestFlight are free and renew on a speeded-up clock, so you can watch a trial start, renew and lapse in under an hour.

## App Store review checklist

- Privacy policy at a public address. Any app that uses HealthKit must have one. The app keeps data on the phone and sends nothing anywhere, and the policy should say exactly that.
- The subscription must be described in the store listing: what it unlocks, the price and period, and links to the terms and privacy policy.
- In review notes, say the app has a readiness check before the plan starts and is training guidance, not medical advice. Keep that wording in the store description too.
- App Privacy section: as written the app collects nothing off the device.
- Screenshots, an icon and a support address.
- Apple keeps a share of every subscription payment. Look up the current rate and the Small Business Program before you set prices.

## Before real people pay for it

1. Get the build and tests green.
2. Check every evidence note in `SessionLibrary.swift`.
3. On a real phone: setup, start the trial, log a run, import from Health, check the paces move as expected, cancel, let it lapse and confirm the paywall returns with your data intact, then Restore.
4. Try the Watch export on a paired watch.
5. Test at the largest text size, in dark mode, and with Health access refused.

## What is in the folder

| Path | What it does |
| --- | --- |
| `project.yml` | Recipe for the Xcode project (targets, HealthKit, privacy text). |
| `.github/workflows/build.yml` | Builds and tests on GitHub's Macs. |
| `RaiseTheBarApp.swift` | App entry, the setup / paywall / app switch, and the three tabs. |
| `Models/` | Runner profile, plan session, benchmark entry. |
| `Engine/` | Pace maths, adaptation, feedback reader, plan generator, session library, fuelling. |
| `Services/SubscriptionStore.swift` | Subscriptions and the settings you must change. |
| `Services/` (others) | Apple Health import, Watch export, coach summary. |
| `Views/` | Setup, Paywall, Plan, Session, Library, Progress, Coach, Me. |
| `Tests/` | Unit tests for the engine. |

## Ideas for later

- A free trial that needs no payment details (the app counts the days itself). Friendlier, but easier to cheat by reinstalling.
- Pace alerts in the Watch export.
- iCloud sync between a runner's own devices.
- An Android or web version would need its own payments and an account system; nothing here carries over except the plan logic.
