# Link Checker API

A web service that takes an input of URIs. It performs a number of checks on
them to determine whether these are things that should be linked to.

## Nomenclature

- **Link**: The consideration of a URI and all resulting redirects
  that may occur from it.
- **Check**: The process of taking a URI and checking it as a Link
  for any problems that may affecting linking to it within content.
- **Batch**: The functionality to check multiple URIs in a grouping

## Technical documentation

This is a Ruby on Rails application that acts as web service for performing
links. Communication to and from this service is done through a RESTful JSON
API. The majority of link checking is done through a background worker than
uses Sidekiq. There is a webhook functionality for applications to receive
notifications when link checking is complete.

📖 The HTTP API is defined in [docs/api.md](docs/api.md).

### Dependencies

- [PostgreSQL](https://www.postgresql.org/) - provides a database
- [redis](https://redis.io) - provides queue storage for Sidekiq jobs

### Running the application

Start the web app with:

```bash
$ ./startup.sh
```

Application will be available on port 3208 - http://localhost:3208 or if you
are using the development VM http://link-checker-api.dev.gov.uk

Start the Sidekiq worker with:

```bash
$ bundle exec sidekiq -C config/sidekiq.yml
```

### Running the test suite

```bash
$ bundle exec rspec
```

### Report rake task

```bash
$ bundle exec rake report[<output-filename>.csv]
```

This will produce a report of all broken links stored in the link checker and when they were last checked.

## Licence

[MIT License](LICENSE)
