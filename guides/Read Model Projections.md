# Read model projections

Your read model can be built using a Commanded event handler and whichever storage provider you prefer. You can choose to use a SQL or NoSQL database, document store, the filesystem, a full text search index, or any other storage mechanism. You may even use multiple storage providers, optimised for the querying they must support.

I typically use Ecto, and a PostgreSQL database, for read model projections. You can use the `project` macro from the [Commanded Ecto projections](https://github.com/slashdotdash/commanded-ecto-projections) library to build projectors, and have the at-least-once event delivery taken care of for you.
