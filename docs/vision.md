# Vision

This project aims to build an open-source CRM platform for county Democratic parties using WordPress and CiviCRM. Columbia County Democrats (Columbia County, Wisconsin) will serve as the prototype. The long-term goal is a reusable platform that integrates volunteer management, email, donations, events, and websites while interoperating with NGP VAN and Action Network.

The memorandum below describes the vision for this project in more detail.

## Memorandum

**To:** Columbia County Democrats Communications Committee and Executive Board
**From:** Sheldon Rampton
**Subject:** Long-Term CRM Strategy for the Columbia County Democrats

### Background

As we've continued to grow our communications and organizing efforts, we've accumulated a variety of systems for managing information. We currently use Mailchimp for our email newsletter, spreadsheets for volunteer management and other contact lists, NGP VAN for voter data and canvassing, and we are now being encouraged by the state Democratic Party to adopt Action Network for email and organizing. We also have separate lists for donors, media contacts, elected officials, and other groups.

Each of these systems serves a purpose, but together they create a patchwork of disconnected information. The same person may appear in multiple databases with different information, and it can be difficult to know which system contains the most up-to-date record. Over time, this becomes increasingly difficult to manage.

I think it is worth considering whether we should eventually move toward a Customer (or Contact) Relationship Management (CRM) system that serves as a single source of truth for the organization.

### What Is a CRM?

Some people have asked why we can't simply continue using spreadsheets.

Spreadsheets are excellent tools for storing lists of information, but they are not designed to manage ongoing relationships with people. A CRM is designed specifically for that purpose.

Instead of simply storing names and email addresses, a CRM allows an organization to keep track of interactions over time:

* volunteer interests and participation
* event attendance
* donations
* committee memberships
* media relationships
* elected officials
* newsletter subscriptions
* conversations and follow-up
* campaign activities
* document attachments and notes

A CRM makes it possible to see the complete history of an organization's relationship with a person rather than scattering that information across multiple spreadsheets and software systems.

It's also worth noting that there are many different kinds of CRM systems, each designed for a different type of organization.

For example, Salesforce is probably the best-known CRM. It is primarily a **Customer Relationship Management** system designed to help businesses manage sales leads, customers, and revenue.

During my years volunteering with nonprofit organizations, I built several custom databases using FileMaker Pro. Those functioned as **Contact Relationship Management** systems that helped organizations manage volunteers, donors, media contacts, board members, and other stakeholders.

Later, while working for the New York State Senate, I was part of the development team that built a statewide **Constituent Relationship Management** system using CiviCRM. That system manages information for more than seven million households across New York State, including constituent contact information, case reports, correspondence, legislative requests, and many other interactions between constituents and Senate offices.

These experiences have convinced me that a well-designed CRM can become one of an organization's most valuable long-term assets.

### CiviCRM

One option I believe deserves serious consideration is CiviCRM.

CiviCRM is an open-source CRM specifically designed for nonprofit organizations, advocacy groups, membership organizations, and political organizations. Unlike commercial CRM systems, there are no licensing fees, and because the software is open source it can be customized to meet an organization's specific needs.

One particularly attractive feature is that CiviCRM integrates extremely well with WordPress.

Today we pay separately for Squarespace to host our website and Mailchimp to manage our email newsletter. A WordPress/CiviCRM installation could potentially replace both systems while providing a fully integrated CRM, website, email management, event registration, volunteer management, and donation platform.

Hosting costs for a WordPress/CiviCRM installation would likely be lower than what we currently spend on Squarespace and Mailchimp combined, while giving us considerably more flexibility.

Because it is open source, we would also have complete ownership of our own data and could customize workflows and features as our needs evolve rather than adapting ourselves to the limitations of commercial software.

### The Biggest Concern: Long-Term Maintainability

The primary drawback of this approach is not the software itself but maintaining customized software over time.

Over the years I've become increasingly cautious about building bespoke software solutions for nonprofit organizations and friends. Software always evolves. Security updates are released. New features become desirable. Integrations change. Every custom system eventually requires maintenance.

The greatest risk is that if I were to become unavailable someday, another volunteer might inherit custom code that they did not write and would therefore find difficult to support.

That concern has made me reluctant to recommend heavily customized software projects unless there is a realistic plan for maintaining them over the long term.

### Why This May Be More Practical Today

I think that concern is becoming more manageable than it once was.

First, we are fortunate to have several members of the Columbia County Democrats communications committee with significant technical experience. That gives us a broader base of expertise than many volunteer organizations enjoy.

Second, recent advances in artificial intelligence are dramatically changing software development. AI-assisted programming—or what is increasingly called "vibe coding"—makes it much easier to understand, extend, and maintain existing code than was possible only a few years ago. AI tools are particularly good at helping developers understand unfamiliar code bases, generate documentation, and implement new features.

One of the reasons this project appeals to me personally is that I would like to gain more hands-on experience building and maintaining software using these new AI-assisted development techniques.

I also think there is an opportunity to create something that could benefit organizations beyond Columbia County. If we can develop a practical CRM architecture that works well for our county party, it may be possible to replicate that solution for other county Democratic parties facing many of the same organizational challenges.

### Recommendation

Although I think a CiviCRM-based solution has considerable long-term promise, I do **not** recommend trying to replace our current systems immediately.

Instead, I recommend that we continue moving forward with the tools already supported by the Democratic Party:

* NGP VAN for voter data and canvassing
* Action Network for email, advocacy, and volunteer engagement
* Mobilize for event management and volunteer recruitment
* our existing spreadsheets where appropriate during the transition

In parallel, I would like to begin developing a CiviCRM prototype.

The goal would not be to deploy it immediately, but rather to explore whether it can serve as a long-term "single source of truth" for the Columbia County Democrats while integrating effectively with the Democratic Party's organizing tools.

Building a prototype would allow us to evaluate the approach without disrupting our existing operations. If it proves successful, we could adopt pieces of it incrementally over time rather than attempting a risky, all-at-once migration.

I believe this balanced approach allows us to take advantage of the Democratic Party's existing organizing infrastructure today while exploring whether a more unified, affordable, and customizable CRM platform could better serve our organization in the years ahead.
