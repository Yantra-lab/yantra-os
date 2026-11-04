# 20. Money

Money is a building block, not an app. Every model call, GPU second, message and payment
is metered into one ledger: who used what, for whom, under which grant. Budgets are
grants (§0.4). This is what lets Yantra give agents and models to millions of people and
businesses and keep control. **planned**, except where noted.

## 20.1 Amounts

- Each currency is its own type, so rupees never mix with dollars: `₹5 + $5` does not
  compile. **built**
- Amounts are exact (`numeric`), never floating point. **built**

## 20.2 The ledger

```text
record Entry
  ledger                         # append-only; each entry is chained to the one before by its hash
  at: Time = now
  account: Account
  amount: INR                    # positive in, negative out
  for: Object?                   # the order, the model call, the job it pays for
  under: Grant?                  # the grant that allowed it
  by: User = me
```

- An entry is never changed or deleted. A mistake is put right by a new entry.
- Every transfer is two entries that sum to zero, written in one transaction (**built**:
  serializable `atomic`, run again on conflict).
- A chain of hashes makes a missing or altered entry visible to anyone who checks.

## 20.3 Metering

Each of these writes an entry, against the grant that allowed it:
- a call to a model (§12), at the provider's cost;
- GPU seconds used by a job;
- storage and traffic of a space, per month;
- a message sent to someone outside Yantra (SMS, mail);
- a payment taken or a refund made (§20.4).

A person, an app, an agent and a space can each see what they used, and for what.

## 20.4 Payments

A payment company is a provider behind a grant: `may take payment through y:@asha-store's
payments`. Money comes in as entries; the shop's balance is a total over its entries
(**built**: `total`), never a number kept by hand.

## 20.5 Budgets

A budget is a grant with a limit per day, per month, or in all:
- `@tutor may call model image, up to ₹300 a day`;
- `app y:@cy/game may use the GPU, up to 2 hours a month`.
At the limit, the action stops, or goes for approval (§19.4).

## 20.6 Tests

Planned (each one is a task):
- A transfer writes two entries that sum to zero, or none.
- An entry cannot be updated or deleted, by anyone.
- Changing an old entry's amount in the table directly breaks the hash chain, and the
  check finds where.
- A model call writes one entry against its grant; at the grant's daily limit the next
  call is refused before it runs.
- A shop's balance equals the total of its entries after 1,000 random orders and refunds.
