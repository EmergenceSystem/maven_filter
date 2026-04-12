# maven_filter
[![License](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](LICENSE.md)

An [em_filter](https://hex.pm/packages/em_filter) agent that searches [Maven Central](https://search.maven.org/) for Java/JVM artifacts and returns results as [Emergence](https://github.com/EmergenceSystem/em_disco) results.

## Query

Any groupId, artifactId, keyword, or `g:a` coordinate accepted by the Maven Central Solr search API.

| Field | Source | Example |
|---|---|---|
| title | `groupId:artifactId` | `com.google.guava:guava` |
| resume | group + version + packaging | `com.google.guava v33.4.0 (jar)` |
| url | Maven Central artifact page | `https://search.maven.org/artifact/...` |
| source | `maven.org` | |

Up to 10 results are returned per query.

## Usage

**Via curl (direct to em_disco):**

```bash
# Search by artifactId
curl -X POST http://localhost:8080/query \
  -H "Content-Type: application/json" \
  -d '{"value": "jackson-databind", "capabilities": ["maven"]}'

# Search by groupId
curl -X POST http://localhost:8080/query \
  -H "Content-Type: application/json" \
  -d '{"value": "org.springframework", "capabilities": ["maven"]}'

# Full coordinate
curl -X POST http://localhost:8080/query \
  -H "Content-Type: application/json" \
  -d '{"value": "g:com.google.guava a:guava", "capabilities": ["maven"]}'
```

**Via Erlang shell:**

```erlang
emquest_cli:query(<<"guava">>).
emquest_cli:query(<<"kotlin coroutines">>).
```

## Installation

```bash
git clone https://github.com/EmergenceSystem/maven_filter.git
cd maven_filter
rebar3 shell --apps maven_filter
```

Requires `em_disco` running on `localhost:8080` (configured in `emergence.conf`).

## Capabilities

`search`, `query`, `maven`, `java`, `jvm`, `kotlin`, `scala`, `packages`

## License

Apache 2.0 — see [LICENSE.md](LICENSE.md).
