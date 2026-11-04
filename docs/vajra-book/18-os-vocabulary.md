# 18. The OS vocabulary

The records every app shares: a person's files, contacts, calendar, messages, places,
browsing, devices and settings, and an organisation's drives and directory. Each is a
`shared` record in a library space. It lives once, and an app reaches a person's rows only
as far as the person allowed: none, all, or the rows they chose.

The way it works (`shared`, the permission list in `atlas.allow`, row security, sealed
fields, chunked files, tree paths, ranges, places) is **built**. The records below are
**planned**: they are the first task of this chapter.

## 18.1 What an app gets

- Nothing, by default. An app declares what it uses (`use @yantra/files`), then asks
  (`File.ask()`); the person's shell shows the request. **built** (`shared`, `ask`)
- The person answers: none, all, or exactly the rows they choose. Taking it back takes
  everything back. **built**
- A web site is an app whose name is its origin (`https://example.com`). It sees only its
  own cookies, storage and permissions. **planned**
- An app never lists the people who exist. It finds a person by a handle it was given.
  **built**

## 18.2 The libraries

| Library | Records | Notes |
|---|---|---|
| `@yantra/people` | `Contact`, `Group` | `Contact.person` links to a Yantra person when there is one |
| `@yantra/devices` | `Device`, `Session` | `Session.token` is sealed (§17) |
| `@yantra/files` | `Folder`, `File`, `Tag` | the chunk store (1 MiB chunks under SHA-256, read by range) is **built**; a `Blob` field type over it is **planned**; versions are history |
| `@yantra/web` | `Site`, `Bookmark`, `Visit`, `Cookie`, `Password`, `SitePermission`, `Download` | cookies and passwords are sealed; each site reads only its own |
| `@yantra/time` | `Calendar`, `Event`, `Reminder` | `Event.during` is a range that `unique … per` can keep from overlapping (**built**) |
| `@yantra/talk` | `Conversation`, `Message`, `Typing` | `Typing` is `memory`, `expire after 10s` |
| `@yantra/places` | `Place`, `SavedPlace`, `Trip` | `Point` with a spatial index (**built**) |
| `@yantra/settings` | `Setting`, `Theme` | a setting is for one device, or for all of a person's devices |
| `@yantra/org` | `Drive`, `Directory`, `Policy`, `AuditView` | an organisation is a tree of spaces with roles (**built**) |

Notifications (`atlas.notification`) and app permissions (`atlas.allow`) are **built**
and stay in the system spaces.

## 18.3 The records

```text
record Contact
  name: string
  phones: seq[string]
  emails: seq[string]
  addresses: seq[Address]        # documents (jsonb), matched by member name
  birthday: Date?
  photo: Asset?
  person: User?                  # when this contact is on Yantra
  owner: User = me
  can read, write: owner
  shared
  search name

record Device
  owner: User = me
  kind: DeviceKind               # phone, tablet, laptop, desktop, headset, watch, tv
  name: string
  lastSeen: Time = now
  publicKey: string              # the device's own key, for sync and sealing on the device
  can read, write: owner
  shared

record Folder
  path: TreePath                 # home.photos.2026
  owner: User = me
  readers: seq[User]
  can read, write: owner
  can read: me in readers
  shared

record File
  name: string
  folder: Folder
  bytes: Blob                    # chunked, read by range
  kind: string                   # image/png, text/markdown …
  trashed: Time?                 # in the bin from this moment; gone 30 days later
  owner: User = me
  can read, write: owner
  can read: me in folder.readers
  shared
  search name

record Cookie
  site: Site
  name: string
  value: sealed string
  expires: Time?
  can read, write: site.app      # planned: the site's own app role, and no other
  shared

record Password
  site: Site
  login: string
  secret: sealed string          # never opened for an agent
  owner: User = me
  can read, write: owner
  shared

record Setting
  app: string                    # "" for the shell itself
  key: string
  value: Json
  device: Device?                # none: every device of the person
  owner: User = me
  unique key per owner, app, device
  can read, write: owner
  shared
```

## 18.4 An organisation

- An organisation is a tree of spaces. A role in a space holds in every space under it.
  **built** (`Atlas.placeUnder`)
- A `Drive` is a folder tree that a space owns, not a person; its rows follow the space's
  roles. **planned**
- `Directory` lists the organisation's people to its members only. **planned**
- `Policy` sets retention and legal holds (**built**), and the region the data must stay
  in (**planned**).
- `AuditView` lets the organisation's owners read the change log of its spaces: who
  changed what, when, from which app. Reads of `sensitive` records are logged too.
  **planned**

## 18.5 Tests

Planned (each one is a task):
- An app that did not ask sees no `File`; after the person allows two chosen files, it sees
  exactly those two.
- Site A cannot read site B's `Cookie`, through any query.
- An agent reading `Password` gets the empty value, and `.opened` is false.
- A `File` with `trashed` 31 days ago is gone after `vajra tick`; one trashed 29 days ago
  is still there.
- Two `Setting` rows with the same key, owner, app and device are refused.
- A member of a department's space reads its `Drive`; a person outside the organisation
  does not.
- An owner's `AuditView` shows a change made by an agent, with the agent's handle.
