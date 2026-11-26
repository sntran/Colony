# Contributing to Colony

These are the rules for this repo. I use them for each change.

## The language

Write all text in [ASD-STE100 Simplified Technical English](https://www.asd-ste100.org/):
documents, code comments, names, log text and commit messages.

- Write short sentences: 20 words or fewer for an instruction, 25 words or fewer for a
  description.
- Use the active voice and the present tense.
- Use one word for one meaning, and the same word in all the files. The table of words in
  the plan gives the words of the game: body, player, worker, cell, row, bank, gap, nest,
  support, scent, tick.
- Give one instruction in each sentence, and start it with the verb.
- Do not use the "-ing" form of a verb, except in a technical name.

Write documents in the first person, as I write them.

Add no notes about the tools that helped to write the code or the text.

## The documents

- `README.md` tells what the prototype is, how to start it and how to test it. Keep it
  correct when the behavior changes.
- Each plan is one file in `docs/plans/`. A plan has a number and a short name.
- Each play test has a report in `docs/playtests/`, with the same number and name as its
  plan.
- If a plan does not decide something, select the simplest option. Record it in
  `docs/decisions.md`. Then continue.
- If a test shows a problem in a rule of a plan, change the rule and record the change in
  `docs/decisions.md`.

## The work

- Work on a branch with the number and the name of the plan, for example
  `feat/0001-first-prototype`.
- Do not open a pull request unless I ask for it.
- Stop and ask me only in two cases: a target of the plan cannot be met after real work, or
  a change is necessary in the short description of the game (section 1 of the plan).

## The code

- Use only Erlang and Elixir on the server. Do not add a package that has a NIF or a port.
- Do not use a database.
- Keep all the numbers of the game in `config/game.exs`.
- Use no model, image, sound or font files. All things in the world come from code.
- Do not add a build step for the page. The files in `priv/static` are the files that the
  browser gets.
- Each rule of the world has a contract in TLA+ in `specs/`. For a change of a rule,
  change the contract first and run `mix colony.contracts`. Then change the code.
- Give each change of a rule a test in `test/`. The tests run the world with no browser.
- Run `mix format` and `mix test` before each commit.
