# Social-media monitoring recommendation

## Recommended first release

Use a consent-based, monthly verified snapshot rather than promising full automatic tracking.

At enrolment, record each participant's TikTok, Instagram and Facebook business profile, the baseline month, follower count, post count, reach or views, engagements and a screenshot or source link. Repeat the same measures monthly for 12 months. Participants can submit evidence; mentors verify unusual changes and tagged campaign posts.

The version 5 database upgrade includes inactive, future-ready `m_social_accounts` and `m_social_snapshots` tables for this model. They are not exposed in the portal navigation until the monitoring definitions and consent wording are approved.

## Why tagging alone is insufficient

- A tag confirms that a post mentions the programme, but it does not consistently provide account-wide reach, views or engagement.
- Participants may use personal accounts that are unavailable to official insights APIs.
- Deleted posts, private profiles, changed handles and expired authorisations create gaps.
- Raw likes cannot be compared fairly across businesses of very different audience sizes.

Use these indicators instead:

- follower growth from baseline;
- posts published per month;
- total reach or views per month;
- total engagements per month;
- engagement rate, using one agreed denominator;
- number of programme-tagged posts;
- evidence status: self-reported, mentor-verified or API-sourced.

## Automation position

TikTok requires a developer application, approved products/scopes and each participant's authorisation. Its Display API can return authorised profile and public-video information; additional statistics require the relevant scopes.

Meta's Instagram integration is designed for professional Business or Creator accounts. Insights access requires participant authorisation and platform permissions; consumer accounts are not supported by the professional API workflow. Facebook Page insights similarly require Page access and permissions.

Therefore, API automation should be a later opt-in pilot for participants with eligible business accounts. It should not be a contractual dependency for the initial 12-month monitoring process.

## Practical decision

Launch the manual verified workflow first. After two or three reporting months, assess how many participants have eligible professional accounts and are willing to connect them. Build API integrations only if that coverage is high enough to justify app review, token management, scheduled data collection, privacy notices and support costs.

Official references:

- TikTok Display API: https://developers.tiktok.com/docs/en/display-api-overview
- TikTok API scopes: https://developers.tiktok.com/docs/en/tiktok-api-scopes
- Meta Instagram API collection: https://www.postman.com/meta/instagram/documentation/6yqw8pt/instagram-api
