# Commanded

Use Commanded to build your own Elixir applications following the [CQRS/ES](http://cqrs.nu/Faq) pattern.

Provides support for:

- Command registration and dispatch.
- Hosting and delegation to aggregates.
- Event handling.
- Long running process managers.

Commanded provides a solid technical foundation for you to build on. It allows you to focus on modelling your domain, the most important part of your app, creating a better application at a faster pace.

You can use Commanded with one of the following event stores for persistence:

- [EventStore](https://github.com/commanded/eventstore) Elixir library, using PostgreSQL for persistence
- Greg Young's [Event Store](https://geteventstore.com/).

Please refer to the [CHANGELOG](CHANGELOG.md) for features, bug fixes, and any upgrade advice included for each release.

---

- [Changelog](CHANGELOG.md)
- [Wiki](https://github.com/commanded/commanded/wiki)
- [Frequently asked questions](https://github.com/commanded/commanded/wiki/FAQ)
- [Getting help](https://github.com/commanded/commanded/wiki/Getting-help)

MIT License

[![Build Status](https://travis-ci.org/commanded/commanded.svg?branch=master)](https://travis-ci.org/commanded/commanded) [![Join the chat at https://gitter.im/commanded/Lobby](https://badges.gitter.im/commanded/Lobby.svg)](https://gitter.im/commanded/Lobby?utm_source=badge&utm_medium=badge&utm_campaign=pr-badge&utm_content=badge)

---

### Overview

- [Getting started](guides/Getting%20Started.md)
- [Choosing an event store](guides/Choosing%20an%20Event%20Store.md)
  - [PostgreSQL-based EventStore](guides/Choosing%20an%20Event%20Store.md#postgresql-based-elixir-eventstore)
  - [Greg Young's Event Store](guides/Choosing%20an%20Event%20Store.md#greg-youngs-event-store)
- [Using Commanded](guides/Usage.md)
  - [Aggregates](guides/Aggregates.md)
    - [Example aggregate](guides/Aggregates.md#example-aggregate)
    - [`Commanded.Aggregate.Multi`](guides/Aggregates.md#using-commandedaggregatemulti-to-return-multiple-events)
    - [Aggregate state snapshots](guides/Aggregates.md#aggregate-state-snapshots)
  - [Commands](guides/Commands.md)
    - [Command handlers](guides/Commands.md#command-handlers)
    - [Command dispatch and routing](guides/Commands.md#command-dispatch-and-routing)
      - [Define aggregate identity](guides/Commands.md#define-aggregate-identity)
      - [Multi-command registration](guides/Commands.md#multi-command-registration)
      - [Dispatch timeouts](guides/Commands.md#timeouts)
      - [Dispatch consistency guarantee](guides/Commands.md#command-dispatch-consistency-guarantee)
      - [Dispatch returning execution result](guides/Commands.md#dispatch-returning-execution-result)
      - [Aggregate lifespan](guides/Commands.md#aggregate-lifespan)
      - [Composite command routers](guides/Commands.md#composite-command-routers)
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
- [Deployment](guides/Deployment.md)
  - [Single node deployment](guides/Deployment.md#single-node-deployment)
  - [Multi node cluster deployment](guides/Deployment.md#multi-node-cluster-deployment)
  - [Multi node, but not clustered deployment](guides/Deployment.md#multi-node-but-not-clustered-deployment)
- [Testing with Commanded](guides/Testing.md)
- [Used in production?](#used-in-production)
- [Example application](#example-application)
- [Learn Commanded in 20 minutes](#learn-commanded-in-20-minutes)
- [Event store provider](guides/Choosing%20an%20Event%20Store.md#writing-your-own-event-store-provider)
- [Contributing](#contributing)
- [Need help?](#need-help)

---

## Used in production?

Yes, Commanded is being used in production.

- Case Study: [Building a CQRS/ES web application in Elixir using Phoenix](https://10consulting.com/2017/01/04/building-a-cqrs-web-application-in-elixir-using-phoenix/)

## Example application

[Conduit](https://github.com/slashdotdash/conduit) is an open source, example Phoenix 1.3 web application implementing the CQRS/ES pattern in Elixir. It was built to demonstrate the implementation of Commanded in an Elixir application for the [Building Conduit](https://leanpub.com/buildingconduit) book.

## Learn Commanded in 20 minutes

[Watch Bernardo Amorim introduce CQRS and event sourcing](https://www.youtube.com/watch?v=S3f6sAXa3-c) at Code Beam SF 2018. Including a tutorial on how to implement an Elixir application using these concepts with Commanded.

## Contributing

Pull requests to contribute new or improved features, and extend documentation are most welcome.

Please follow the existing coding conventions, or refer to the [Elixir style guide](https://github.com/niftyn8/elixir_style_guide).

You should include unit tests to cover any changes. Run `mix test` to execute the test suite.

### Contributors

- [Andrey Akulov](https://github.com/astery)
- [Andrzej Sliwa](https://github.com/andrzejsliwa)
- [Ben Smith](https://github.com/slashdotdash)
- [Bernardo Amorim](https://github.com/bamorim)
- [Brenton Annan](https://github.com/brentonannan)
- [Chris Brodt](https://github.com/uberbrodt)
- [David Carlin](https://github.com/davich)
- [Florian Ebeling](https://github.com/febeling)
- [Henry Hazan](https://github.com/henry-hz)
- [Joan Zapata](https://github.com/JoanZapata)
- [Kok J Sam](https://github.com/sammkj)
- [Leif Gensert](https://github.com/leifg)
- [Luís Ferreira](https://github.com/zamith)
- [Olafur Arason](https://github.com/olafura)
- [Patrick Detlefsen](https://github.com/patrickdet)
- [Raphaël Lustin](https://github.com/rlustin)

## Need help?

Please [open an issue](https://github.com/commanded/commanded/issues) if you encounter a problem, or need assistance. You can also seek help in the [Gitter chat room](https://gitter.im/commanded/Lobby) for Commanded.

For commercial support, and consultancy, please contact [Ben Smith](mailto:ben@10consulting.com).
