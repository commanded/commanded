# Commanded

Use Commanded to build your own Elixir applications following the [CQRS/ES](http://cqrs.nu/Faq) pattern.

Provides support for:

- Command registration and dispatch.
- Hosting and delegation to aggregates.
- Event handling.
- Long running process managers.

Commanded provides a solid technical foundation for you to build on. It allows you to focus on modelling your domain, the most important part of your app, creating a better application at a faster pace.

You can use Commanded with one of the following event stores for persistence:

- [EventStore](https://github.com/commanded/eventstore) - Elixir library using Postgres for persistence.
- [EventStoreDB](https://www.eventstore.com/) - a stream database built for Event Sourcing.
- [In-memory event store](https://github.com/commanded/commanded/wiki/In-memory-event-store) - included for test use only.

Please refer to the [CHANGELOG](CHANGELOG.md) for features, bug fixes, and any upgrade advice included for each release.

Requires Erlang/OTP v21.0 and Elixir v1.9 or later.

---

#### Sponsors

- [View sponsors & backers](BACKERS.md)

[![Alembic](https://user-images.githubusercontent.com/3167/177830256-26a74e82-60ff-4c20-bd84-64ee7c12512c.svg "Alembic")](https://alembic.com.au/)

---

- [Changelog](CHANGELOG.md)
- [Wiki](https://github.com/commanded/commanded/wiki)
- [What is CQRS/ES?](https://kalele.io/blog-posts/really-simple-cqrs/)
- [Frequently asked questions](https://github.com/commanded/commanded/wiki/FAQ)
- [Getting help](https://github.com/commanded/commanded/wiki/Getting-help)
- [Latest published Hex package](https://hex.pm/packages/commanded) & [documentation](https://hexdocs.pm/commanded/)

MIT License

[![Build Status](https://github.com/commanded/commanded/workflows/Test/badge.svg?branch=master)](https://github.com/commanded/commanded/actions) [![Join the chat at https://gitter.im/commanded/Lobby](https://badges.gitter.im/commanded/Lobby.svg)](https://gitter.im/commanded/Lobby?utm_source=badge&utm_medium=badge&utm_campaign=pr-badge&utm_content=badge)

---

> This README and the following guides follow the `master` branch which may not be the currently published version.
>
> [Read the documentation for the latest published version of Commanded on Hex](https://hexdocs.pm/commanded/).

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
    - [Composite command routers](guides/Commands.md#composite-command-routers)
  - [Events](guides/Events.md)
    - [Domain events](guides/Events.md#domain-events)
    - [Event handlers](guides/Events.md#event-handlers)
      - [Consistency guarantee](guides/Events.md#consistency-guarantee)
    - [Upcasting events](guides/Events.md#upcasting-events)
  - [Process managers](guides/Process%20Managers.md)
    - [Example process manager](guides/Process%20Managers.md#example-process-manager)
  - [Supervision](guides/Supervision.md)
  - [Serialization](guides/Serialization.md)
    - [Default JSON serializer](guides/Serialization.md#default-json-serializer)
    - [Configuring JSON serialization](guides/Serialization.md#configuring-json-serialization)
    - [Decoding event structs](guides/Serialization.md#decoding-event-structs)
    - [Using an alternative serialization format](guides/Serialization.md#using-an-alternative-serialization-format)
    - [Customising serialization](guides/Serialization.md#customising-serialization)
  - [Read model projections](guides/Read%20Model%20Projections.md)
- [Deployment](guides/Deployment.md)
  - [Single node deployment](guides/Deployment.md#single-node-deployment)
  - [Multi node cluster deployment](guides/Deployment.md#multi-node-cluster-deployment)
  - [Multi node, but not clustered deployment](guides/Deployment.md#multi-node-but-not-clustered-deployment)
- [Testing with Commanded](guides/Testing.md)
- [Used in production?](#used-in-production)
- [Example application](#example-application)
- [Learn Commanded in 20 minutes](#learn-commanded-in-20-minutes)
- [Choosing an event store provider](guides/Choosing%20an%20Event%20Store.md#writing-your-own-event-store-provider)
- [Tooling](https://github.com/commanded/commanded/wiki/Tooling)
- [Contributing](#contributing)
- [Need help?](#need-help)

---

## Used in production?

Yes, see the [companies using Commanded](https://github.com/commanded/commanded/wiki/Companies-using-Commanded).

## Example application

[Conduit](https://github.com/slashdotdash/conduit) is an open source, example Phoenix 1.3 web application implementing the CQRS/ES pattern in Elixir. It was built to demonstrate the implementation of Commanded in an Elixir application for the [Building Conduit](https://leanpub.com/buildingconduit) book.

## Learn Commanded in 20 minutes

[Watch Bernardo Amorim introduce CQRS and event sourcing](https://www.youtube.com/watch?v=S3f6sAXa3-c) at Code Beam SF 2018. Including a tutorial on how to implement an Elixir application using these concepts with Commanded.

## Contributing

Pull requests to contribute new or improved features, and extend documentation are most welcome.

Please follow the existing coding conventions, or refer to the [Elixir style guide](https://github.com/niftyn8/elixir_style_guide).

You should include unit tests to cover any changes. Run `mix test` to execute the test suite.

### Contributors

Commanded exists thanks to the following people who have contributed.

<a href="https://github.com/commanded/commanded/graphs/contributors"><img src="https://opencollective.com/commanded/contributors.svg?width=890&button=false" width="890" /></a>

- [Adil Yarulin](https://github.com/ayarulin)
- [Alexandre de Souza](https://github.com/aleDsz)
- [Andrey Akulov](https://github.com/astery)
- [Andrzej Sliwa](https://github.com/andrzejsliwa)
- [Ben Smith](https://github.com/slashdotdash)
- [Benjamin Moss](https://github.com/drteeth)
- [Bernardo Amorim](https://github.com/bamorim)
- [Brenton Annan](https://github.com/brentonannan)
- [Chris Brodt](https://github.com/uberbrodt)
- [Chris Martin](https://github.com/trbngr)
- [Christophe Juniet](https://github.com/cjuniet)
- [Danilo Silva](https://github.com/silvadanilo)
- [Dave Lucia](https://github.com/davydog187)
- [David Carlin](https://github.com/davich)
- [Damir Vandic](https://github.com/dvic)
- [Danni Friedland](https://github.com/BlueHotDog)
- [Ernesto](https://github.com/lex-mala)
- [Fernando Mendes](https://github.com/justmendes)
- [Florian Ebeling](https://github.com/febeling)
- [Henry Hazan](https://github.com/henry-hz)
- [JC](https://github.com/jccf091)
- [Joan Zapata](https://github.com/JoanZapata)
- [Joao Gilberto Moura](https://github.com/joaobalsini)
- [João Thallis](https://github.com/joaothallis)
- [John Wilger](https://github.com/jwilger)
- [Joseph Lozano](https://github.com/joseph-lozano)
- [Kian-Meng Ang](https://github.com/kianmeng)
- [Kok J Sam](https://github.com/sammkj)
- [Leif Gensert](https://github.com/leifg)
- [Luís Ferreira](https://github.com/zamith)
- [Marcelo Dominguez](https://github.com/marpo60)
- [Matt Doughty](https://github.com/m-doughty)
- [Matthew Boehlig](https://github.com/thetamind)
- [Michael Herold](https://github.com/michaelherold)
- [Miguel Palhas](https://github.com/naps62)
- [Nigel Thorne](https://github.com/nigelthorne)
- [Olafur Arason](https://github.com/olafura)
- [Paolo Laurenti](https://github.com/PaoloLaurenti)
- [Patrick Detlefsen](https://github.com/patrickdet)
- [Phil Chen](https://github.com/fahchen)
- [Raphaël Lustin](https://github.com/rlustin)
- [Štefan Ľupták](https://github.com/EskiMag)
- [Tobiasz Małecki](https://github.com/amatalai)
- [Willy Wombat](https://github.com/octowombat)
- [Yordis Prieto](https://github.com/yordis)
- [Yuri de Figueiredo](https://github.com/y86)
- [Zven](https://github.com/zven21)

## Need help?

Please [open an issue](https://github.com/commanded/commanded/issues) if you encounter a problem, or need assistance. You can also seek help in the #commanded channel in the [official Elixir Slack](https://elixir-slackin.herokuapp.com/).
