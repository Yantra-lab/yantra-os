# 21. The superapp

Yantra does everything a person, a business or a government does on a computer, in one
place, with one identity and one set of records. Each domain is an extension (§0.5) over
shared records (§18), with its views, its lenses (§22) and its agents (§19). Nothing in a
domain is a special case of the core. **planned**, on the foundations §0 lists as built.

## 21.1 The domains

| Domain | Extensions | Shared records it adds |
|---|---|---|
| People | `@yantra/people`, `@yantra/devices`, `@yantra/orgs` | `Contact`, `Group`, `Device`, `Session`, `Org` |
| Files | `@yantra/files` | `Folder`, `File`, `Tag` |
| Talk | `@yantra/talk`, `@yantra/calls` | `Conversation`, `Message`, `Call`, `Community` |
| The web | `@yantra/social`, the kinds (§22.2) | `Post`, `Reaction`, `Follow`, `Video`, `Question`, `App` … |
| Work | `@yantra/docs`, `@yantra/sheets`, `@yantra/slides`, `@yantra/design`, `@yantra/projects`, `@yantra/mail` | `Doc`, `Sheet`, `Deck`, `Design`, `Task`, `Project`, `Mail` |
| Commerce | `@yantra/commerce`, `@yantra/delivery` | `Shop`, `Product`, `Stock`, `Order`, `Invoice`, `Delivery`, `Review` |
| Money | `@yantra/money` (§20) | `Account`, `Entry`, `Payment`, `Budget` |
| Media | `@yantra/studio` (§12), `@yantra/photos`, `@yantra/music`, `@yantra/games` | `Image`, `Clip`, `Song`, `Mesh`, `Game` |
| Learning | `@yantra/learn` | `Course`, `Lesson`, `Exercise`, `Progress` |
| Places | `@yantra/places`, `@yantra/bookings` | `Place`, `Trip`, `Booking` |
| Health | `@yantra/health` | `Reading`, `Visit`, `Prescription` (all `sensitive`, §17) |
| Public | `@yantra/public` | `Application`, `Approval`, `Certificate`, `Notice` |

## 21.2 One row, many views

A buyer's order is one `Order` row:
- the shop sees it on its dashboard;
- the buyer sees it in their orders;
- the shopkeeper agent sees it in that buyer's thread;
- the delivery app sees the address and the parcel, and nothing else.

Each sees the row as its grants allow (§0.4). Nothing is copied between apps, so nothing
falls out of step.

## 21.3 One identity, many roles

A person is one `User` everywhere: a buyer in one shop, the owner of another, a teacher in
a school's space, a citizen in a ministry's, a player in a game. Their roles come from the
spaces they belong to (**built**), and their data stays theirs: an app or a shop reaches it
only as far as they allowed (`shared`, **built**).

## 21.4 Apps on every device

The same apps run on the Yantra OS and in the Yantra app on every other system (§0.2).
A person's spaces sync between their devices in real time, offline first (§8).

## 21.5 Tests

Planned (each one is a task):
- An `Order` created by the shopkeeper agent appears in the buyer's orders and on the
  shop's dashboard, as one row; the delivery app reads its address and parcel only.
- A person who is a buyer in one shop and the owner of another sees each shop's records as
  that role allows, in one session.
- A domain extension installs in an empty space, and its tests pass, without changing the
  core.
