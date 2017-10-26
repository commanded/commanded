# Commanded

Use Commanded to build your own Elixir applications following the [CQRS/ES](http://cqrs.nu/Faq) pattern.

Provides support for:

- Command registration and dispatch.
- Hosting and delegation to aggregate roots.
- Event handling.
- Long running process managers.

You can use Commanded with one of the following event stores for persistence:

- [EventStore](https://github.com/slashdotdash/eventstore) Elixir library, using PostgreSQL for persistence
- Greg Young's [Event Store](https://geteventstore.com/).

Please refer to the [CHANGELOG](CHANGELOG.md) for features, bug fixes, and any upgrade advice included for each release.

---

- [Changelog](CHANGELOG.md)
- [Wiki](https://github.com/slashdotdash/commanded/wiki)
- [Frequently asked questions](https://github.com/slashdotdash/commanded/wiki/FAQ)
- [Getting help](https://github.com/slashdotdash/commanded/wiki/Getting-help)

MIT License

[![Build Status](https://travis-ci.org/slashdotdash/commanded.svg?branch=master)](https://travis-ci.org/slashdotdash/commanded) [![Join the chat at https://gitter.im/commanded/Lobby](https://badges.gitter.im/commanded/Lobby.svg)](https://gitter.im/commanded/Lobby?utm_source=badge&utm_medium=badge&utm_campaign=pr-badge&utm_content=badge)

---

### Overview

- [Getting started](guides/Getting%20Started.md)
- [Choosing an event store](guides/Choosing%20an%20Event%20Store.md)
  - [PostgreSQL-based EventStore](guides/Choosing%20an%20Event%20Store.md#postgresql-based-elixir-eventstore)
  - [Greg Young's Event Store](guides/Choosing%20an%20Event%20Store.md#greg-youngs-event-store)
- [Using Commanded](guides/Usage.md)
  - [Aggregate roots](guides/Aggregate%20Roots.md)
    - [Example aggregate root](guides/Aggregate%20Roots.md#example-aggregate-root)
    - [`Commanded.Aggregate.Multi`](guides/Aggregate%20Roots.md#using-commandedaggregatemulti-to-return-multiple-events)
  - [Commands](guides/Commands.md)
    - [Command handlers](guides/Commands.md#command-handlers)
    - [Command dispatch and routing](guides/Commands.md#command-dispatch-and-routing)
      - [Define aggregate identity](guides/Commands.md#define-aggregate-identity)
      - [Multi-command registration](guides/Commands.md#multi-command-registration)
      - [Dispatch timeouts](guides/Commands.md#timeouts)
      - [Dispatch consistency guarantee](guides/Commands.md#command-dispatch-consistency-guarantee)
      - [Dispatch returning execution result](guides/Commands.md#dispatch-returning-execution-result)
      - [Aggregate lifespan](guides/Commands.md#aggregate-lifespan)
    - [Middleware](guides/Commands.md#middleware)
      - [Example middleware](guides/Commands.md#example-middleware)
  - [Events](guides/Events.md)
    - [Domain events](guides/Events.md#domain-events)
    - [Event handlers](guides/Events.md#event-handlers)
      - [Consistency guarantee](guides/Events.md#consistency-guarantee)
  - [Process managers](guides/Process%20Managers.md)
    - [Example process manager](guides/Process%20Managers.md#example-process-manager)
  - [Supervision](guides/Supervision.md)
  - [Serialization](guides/Serialization.md)
  - [Read model projections](guides/Read%20Model%20Projections.md)
- [Used in production?](#used-in-production)
- [Example application](#example-application)
- [Limitations](#limitations)
- [Event store provider](guides/Choosing%20an%20Event%20Store.md#writing-your-own-event-store-provider)
- [Contributing](#contributing)
- [Need help?](#need-help)

---

## Used in production?

Yes, Commanded is being used in production.

- Case Study: [Building a CQRS/ES web application in Elixir using Phoenix](https://10consulting.com/2017/01/04/building-a-cqrs-web-application-in-elixir-using-phoenix/)

## Example application

[Conduit](https://github.com/slashdotdash/conduit) is an open source, example Phoenix 1.3 web application implementing the CQRS/ES pattern in Elixir. It was built to demonstrate the implementation of Commanded in an Elixir application for the [Building Conduit](https://leanpub.com/buildingconduit) book.

## Limitations

Commanded is currently limited to running on a single node. Support for running on a cluster of nodes ([#39](https://github.com/slashdotdash/commanded/issues/39)) is under active development.

## Contributing

Pull requests to contribute new or improved features, and extend documentation are most welcome.

Please follow the existing coding conventions, or refer to the [Elixir style guide](https://github.com/niftyn8/elixir_style_guide).

You should include unit tests to cover any changes. Run `mix test` to execute the test suite.

### Contributors

- [Andrey Akulov](https://github.com/astery)
- [Brenton Annan](https://github.com/brentonannan)
- [Olafur Arason](https://github.com/olafura)
- [Chris Brodt](https://github.com/uberbrodt)
- [David Carlin](https://github.com/davich)
- [Patrick Detlefsen](https://github.com/patrickdet)
- [Florian Ebeling](https://github.com/febeling)
- [Leif Gensert](https://github.com/leifg)
- [Henry Hazan](https://github.com/henry-hz)
- [Raphaël Lustin](https://github.com/rlustin)
- [Kok J Sam](https://github.com/sammkj)
- [Andrzej Sliwa](https://github.com/andrzejsliwa)
- [Joan Zapata](https://github.com/JoanZapata)

## Need help?

Please [open an issue](https://github.com/slashdotdash/commanded/issues) if you encounter a problem, or need assistance. You can also seek help in the [Gitter chat room](https://gitter.im/commanded/Lobby) for Commanded.

For commercial support, and consultancy, please contact [Ben Smith](mailto:ben@10consulting.com).
