# Data Model

**Version:** 0.1 (Draft)

This document describes the major CiviCRM entities used by the CoCoDems CRM and how they relate to one another. CiviCRM is the canonical database for organizational information; see [architecture.md](architecture.md) for data-ownership principles.

CiviCRM terminology is used throughout. Where Columbia County Democrats concepts do not map one-to-one to stock CiviCRM objects, the recommended modeling approach is noted.

---

# Core Entity Overview

```
                    ┌─────────────┐
                    │  Contact    │
                    │ (base type) │
                    └──────┬──────┘
           ┌───────────────┼───────────────┐
           │               │               │
    ┌──────▼──────┐ ┌──────▼──────┐ ┌──────▼──────┐
    │ Individual  │ │Organization │ │  Household  │
    └──────┬──────┘ └──────┬──────┘ └──────┬──────┘
           │               │               │
           └───────────────┼───────────────┘
                           │
              ┌────────────┼────────────┐
              │            │            │
       ┌──────▼──────┐ ┌───▼───┐ ┌──────▼──────┐
       │Relationship │ │ Group │ │ Tag / Custom│
       └─────────────┘ └───────┘ │    Field    │
                                  └─────────────┘

    ┌──────────┐  ┌──────────┐  ┌──────────────┐  ┌─────────────┐
    │ Activity │  │  Event   │  │ Contribution │  │ Membership  │
    └────┬─────┘  └────┬─────┘  └──────┬───────┘  └──────┬──────┘
         │             │               │                  │
         └─────────────┴───────────────┴──────────────────┘
                           │
                    (linked to Contact)
```

---

# Contacts

A **Contact** is the central record in CiviCRM. Every person, organization, or household the county party interacts with is stored as a contact.

## Contact subtypes

| Subtype | CiviCRM type | Use in CoCoDems |
|---------|--------------|-----------------|
| Person | Individual | Volunteers, donors, members, activists, staff |
| Organization | Organization | Local unions, businesses, partner nonprofits, media outlets, government bodies |
| Household | Household | Shared address groupings (e.g., spouses at one address) |

### Individual contacts

Individuals represent single people. Typical fields:

* name (prefix, first, middle, last, suffix, nickname)
* email (primary, alternate)
* phone (mobile, home, work)
* address (home, work, mailing)
* communication preferences and GDPR/consent flags

**CoCoDems-specific modeling:**

| Concept | Recommended approach |
|---------|---------------------|
| Volunteer | Tag `Volunteer` and/or custom field set "Volunteer Profile" (interests, availability, skills) |
| Donor | Tag `Donor`; link **Contributions** (see below) |
| Media contact | Tag `Media`; custom fields for outlet, beat, preferred contact method |
| Elected official | Tag `Elected Official`; custom fields for office, district, term dates |
| Committee member | **Relationship** to committee (Organization or Group) + role field |
| Newsletter subscriber | **Group** `Newsletter Subscribers` and/or CiviMail subscription |

One person may hold several roles simultaneously (e.g., volunteer and donor). Use tags, groups, and relationships rather than duplicating contact records.

### Organization contacts

Organizations represent entities, not people. Examples:

* *Columbia County Chronicle* (media outlet)
* a local union or advocacy group
* the Wisconsin Democratic Party (state party)
* a municipal office (as an institution, not the officeholder)

Link individuals to organizations with **Employee of**, **Volunteer for**, or **Media contact at** relationships.

### Household contacts

Households group individuals who share a mailing address or should receive one piece of mail.

* One household contact holds the shared address.
* Individual contacts are linked as **Household Member** relationships.
* Use households for joint donation acknowledgments and household-level mailings.

Do not create a household for every individual — only where shared mail or joint reporting is needed.

---

# Relationships

**Relationships** connect two contacts with a typed, directional link.

| Relationship type | From → To | Example |
|-------------------|-----------|---------|
| Household Member | Individual → Household | Jane Doe → Doe Household |
| Employee of | Individual → Organization | Reporter → Local newspaper |
| Volunteer for | Individual → Organization | Activist → County party |
| Committee member of | Individual → Organization | Member → Finance Committee |
| Spouse of | Individual ↔ Individual | (bidirectional) |
| Media contact at | Individual → Organization | Press contact → TV station |
| Elected to | Individual → Organization | Supervisor → Columbia County Board |

Relationship types should be configured once in CiviCRM and reused consistently. Prefer standard CiviCRM relationship types where they exist; add custom types only when necessary.

Relationships can have start and end dates — use these for term-limited roles (committee chairs, elected terms).

---

# Groups

**Groups** are flat or nested collections of contacts used for mailings, permissions, and reporting.

| Group | Purpose |
|-------|---------|
| Newsletter Subscribers | Email list for regular communications |
| Active Volunteers | People currently available for shifts |
| Executive Board | Members with board-level access or reporting |
| Event volunteers | Pool for event staffing |
| Legacy / imported | Temporary groups during data migration for review before merge |

Groups can be **Smart Groups** (dynamic, query-driven) or **Manual Groups** (explicitly managed).

Example smart group: *Individuals tagged Volunteer with custom field Availability = Weekends*.

Use groups for mailing lists and bulk operations. Use tags for classification that cuts across groups.

---

# Tags

**Tags** are lightweight labels applied to contacts, activities, cases, or other entities.

Suggested tag vocabulary (expand as needed):

| Tag | Applied to |
|-----|------------|
| Volunteer | Individual |
| Donor | Individual |
| Media | Individual |
| Elected Official | Individual |
| Precinct Captain | Individual |
| Needs follow-up | Individual, Activity |
| Imported — review | Individual (temporary, during migration) |

Tags are ideal for yes/no classification and cross-cutting filters. Avoid using tags as a substitute for structured data that belongs in custom fields (e.g., "Interest: Canvassing" is better as a custom field or group).

---

# Custom Fields

**Custom fields** extend contacts (and other entities) with structured, searchable data.

Organize custom fields into **Custom Field Sets** attached to the appropriate entity type.

## Suggested field sets

### Volunteer Profile (Individual)

| Field | Type | Notes |
|-------|------|-------|
| Interests | Multi-select | Canvassing, phone banking, events, data entry, etc. |
| Availability | Text or multi-select | Weekdays, weekends, evenings |
| Skills | Multi-select | Graphic design, legal, accounting, etc. |
| Emergency contact | Contact reference or text | Optional |
| Background check date | Date | If applicable |

### Media Profile (Individual)

| Field | Type | Notes |
|-------|------|-------|
| Beat / coverage area | Text | Local government, courts, etc. |
| Preferred contact method | Select | Email, phone, text |
| Twitter / social | Text | |

### Elected Official Profile (Individual)

| Field | Type | Notes |
|-------|------|-------|
| Office title | Text | Chair, Supervisor, etc. |
| District | Text | Ward, municipality, district number |
| Term start / end | Date | |
| Party affiliation | Select | |

### Organization Profile (Organization)

| Field | Type | Notes |
|-------|------|-------|
| Organization type | Select | Media, union, nonprofit, government, vendor |
| Website | URL | |

Custom field names and options should be defined in configuration export (CiviCRM export/import or API) so they can be reproduced in staging and other county deployments.

---

# Committees

CiviCRM has no first-class "Committee" entity. Model committees using one of these patterns:

**Recommended: Organization + Relationships**

* Each committee (Finance, Communications, etc.) is an **Organization** contact.
* Members are linked via **Committee member of** relationships with optional role (Chair, Vice Chair, Member).
* Committee meetings can be logged as **Activities** or **Events**.

**Alternative: Groups**

* Simpler for mailing and reporting only.
* Less expressive for roles, terms, and meeting history.

The custom plugin may provide a committee dashboard that abstracts the underlying Organization + Relationship model.

---

# Activities

**Activities** record interactions and tasks: phone calls, meetings, emails sent, follow-ups.

| Activity type | Use |
|---------------|-----|
| Phone Call | Volunteer outreach, donor thank-you calls |
| Meeting | Committee meeting, one-on-one |
| Email | Logged correspondence (when not tracked by CiviMail) |
| Follow-up | Scheduled reminder for a volunteer or staff member |

Activities link to one or more contacts and optionally to a **Case** (if case management is enabled).

Use activities instead of free-text notes in custom fields when the interaction has a date, assignee, or follow-up date.

---

# Events and Participants

**Events** represent county party gatherings: meetings, fundraisers, canvass launches, training sessions.

| Entity | Role |
|--------|------|
| Event | The scheduled occurrence (date, location, capacity) |
| Participant | Links an Individual contact to an event with status (Registered, Attended, No-show) |
| Participant role | Attendee, Volunteer, Speaker, etc. |

Event registration can originate from:

* CiviCRM event pages (WordPress-embedded)
* Manual entry by staff
* Future Mobilize sync (external registrations imported as participants)

---

# Contributions

**Contributions** track donations linked to Individual (or Organization) contacts.

| Field / concept | Notes |
|-----------------|-------|
| Financial type | Donation, event fee, membership fee |
| Payment instrument | Check, credit card, in-kind |
| Soft credit | Attribute donation influence to another contact (e.g., spouse, fundraiser) |
| Campaign / fund | General, specific event, or election cycle |

Link contributions to **Events** when tied to ticket sales or fundraiser attendance.

---

# Memberships

**Memberships** are optional but useful if the county party has formal membership tiers or dues.

| Concept | CiviCRM mapping |
|---------|-----------------|
| Membership type | e.g., Regular, Lifetime, Honorary |
| Status | Current, Grace, Expired |
| Start / end date | Term tracking |

If the organization does not collect dues, memberships may be unused initially; tags and groups may suffice.

---

# Email and Mailing Lists

CiviCRM **CiviMail** manages email subscriptions and mailings.

| Entity | Purpose |
|--------|---------|
| Mailing list / group | Recipients for a send |
| Mailing | A specific email blast with tracking |
| Mailing event | Open, click, bounce, unsubscribe |

Consent and opt-out status must be preserved during any import from Mailchimp or Action Network. Never re-subscribe someone who has opted out.

---

# Cases (Optional)

**Cases** provide structured workflows (intake → investigation → resolution). Useful for:

* constituent-style inquiries directed at the party
* formal complaints or ethics matters
* complex multi-step volunteer onboarding

Cases are not required for the initial prototype. Enable when a workflow needs assigned roles, statuses, and a timeline beyond simple activities.

---

# External System Mapping

The CRM coexists with external tools. Each system may hold overlapping data; the CRM should be authoritative for organizational contacts.

| External system | CRM entity | Sync direction (target) |
|-----------------|------------|---------------------------|
| NGP VAN | Individual (activist/volunteer subset) | CRM → VAN for volunteer lists; VAN → CRM for contact results (future) |
| Action Network | Individual, Group | Bidirectional for advocates and sign-ups (future) |
| Mobilize | Event, Participant | Mobilize → CRM for registrations (future) |
| Mailchimp | Individual, Group | One-time import; then CRM authoritative |
| Spreadsheets | Individual, Organization | One-time import; then retired |

During migration, use tag `Imported — review` until records are validated and deduplicated.

---

# Data Integrity Rules

1. **One person, one contact.** Merge duplicates rather than maintaining parallel records.
2. **Relationships over duplication.** Link a media contact to their outlet; do not create a new organization record for every article.
3. **Dates on time-limited roles.** Committee memberships and elected terms should have start/end dates.
4. **Consent is sacred.** Email opt-out status must never be overwritten by imports.
5. **Audit trail.** Prefer Activities and CiviCRM logging over undocumented spreadsheet edits.
6. **No secrets in the database.** API tokens and credentials belong in environment configuration, not contact records.

---

# Entity Quick Reference

| CoCoDems concept | Primary CiviCRM entity | Secondary links |
|------------------|-------------------------|-----------------|
| Person | Individual | Tags, custom fields |
| Household | Household + relationships | Shared address |
| Local business / partner | Organization | |
| Media outlet | Organization | Individual via Media contact at |
| Committee | Organization (recommended) | Relationships, Activities |
| Volunteer shift | Event + Participant (role: Volunteer) | Activity log |
| Donation | Contribution | Individual, soft credits |
| Newsletter | Group + CiviMail | Consent fields |
| Phone bank shift | Activity or Event | Assigned contacts |
| Elected official | Individual + tags/fields | Organization (government body) |

For implementation details and API usage, see [architecture.md](architecture.md) and [coding-standards.md](coding-standards.md).
