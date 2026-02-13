# RESO API

Ruby wrapper for easy interaction with a RESO Web API compliant server.

This document does not documentation for the RESO Web API. More information about the RESO Web API standard can be found on [RESO][]'s website.

[RESO]: https://www.reso.org/reso-web-api/

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'reso_api'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install reso_api

## Usage

### Authentication and Access

This gem supports two types of authentication:

- OAuth2
- Access Token

#### OAuth2

To set up an API client using OAuth2 authentication, you need four pieces of information:

- Client ID
- Client Secret
- Authentication URL
- Base URL

Often, the base URL ends with `/odata`, and the authentication URL often ends with `/token`.

There are two additional pieces of information that are not required:

- Scope
- Originating System Name (OSN)

Scope defaults to "api" and only needs to be included if it is "OData" or something else.

Some MLS systems require Originating System Name to be included in requests.

You pass these 4—6 pieces of information to create an instance of an API client:

```ruby
client = RESO::API::Client.new(client_id: client_id, client_secret: client_secret, auth_url: auth_url, base_url: base_url, scope: scope, osn: osn)
```

When calling API endpoints using the initialized client, it will automatically fetch and manage access and authentication tokens transparently in the background.

#### Access Token

Some systems, like MLSGRID and Spark/Flexmls provides a persistent Access Token. In these cases, you need these two pieces of information to set up an API client:

- Access Token
- Base API endpoint

You pass these two pieces of information to create an instance of an API client:

```ruby
client = RESO::API::Client.new(access_token: access_token, base_url: base_url)
```

#### Base URL for Replication

Some systems, like Bridge Interactive, provide replication endpoints that differ from the ones for normal search requests by including an additional path segment *following* the resource segment. For example:

    https://api.bridgedataoutput.com/api/v2/OData/{dataset_id}/Property/replication

To accommodate this, the `base_url` parameter may contain a `/$resource$` segment which will be replaced for each API call with the appropriate resource segment.


### Resources

#### Supported Resources

- Media
- Member
- Office
- Property

### Retrieving Metadata

You can fetch metadata for supported resources:

```ruby
client.metadata
```

The response will be an EDMX xml schema document that matches the [RESO Data Dictionary standard][].

[RESO Data Dictionary standard]: https://www.reso.org/data-dictionary/

### Query Builder (ActiveRecord-style)

Calling a resource method with no arguments returns a query builder that supports chainable, ActiveRecord-style queries. Results are returned as unwrapped arrays (the contents of `value` from the OData response).

For properties, a default scope of `StandardStatus in ('Active','Pending')` is automatically applied unless you specify `StandardStatus` yourself or call `.unscoped`.

#### Basic queries

```ruby
# Returns array of listing hashes (default scope: Active + Pending)
listings = client.properties.where(City: "Seattle")

# Chained conditions (joined with 'and')
listings = client.properties
  .where(City: "Seattle")
  .where(["ListPrice >= ?", 500_000])

# Single record lookup
listing = client.properties.find_by(ListingId: "123456")

# Lookup by primary key (uses detail endpoint)
listing = client.properties.find("3yd-BINDER-5508272")

# First record
listing = client.properties.where(City: "Seattle").first

# Count
total = client.properties.where(City: "Seattle").count
```

#### Where conditions

**Hash conditions** — equality, IN, ranges, and string matching:

```ruby
.where(City: "Seattle")                          # City eq 'Seattle'
.where(StandardStatus: ['Active', 'Pending'])     # StandardStatus in ('Active','Pending')
.where(ListPrice: 300_000..500_000)               # ListPrice ge 300000 and ListPrice le 500000
.where(ListPrice: 300_000..)                      # ListPrice ge 300000
.where(ListPrice: ..500_000)                      # ListPrice le 500000
```

**String matching** — use `%` wildcards like SQL `LIKE`:

```ruby
.where(ListOfficeName: "Slifer%")                 # startswith(ListOfficeName,'Slifer')
.where(ListOfficeName: "%Frampton")               # endswith(ListOfficeName,'Frampton')
.where(ListOfficeName: "%Smith%")                 # contains(ListOfficeName,'Smith')
.where(ListOfficeName: "Slifer Smith & Frampton") # exact match (no %)
```

Only `%` at the first and/or last position is treated as a wildcard. A `%` in the middle of the string (e.g. `"100% Pure"`) is treated literally. To match a literal `%` at the start or end, escape it with `\%`.

**Note:** Not all MLS servers support all string functions. `startswith` has the widest support. Some servers silently return empty results for `endswith` and `contains` rather than an error.

**Array conditions** — comparison operators with `?` placeholders:

```ruby
.where(["CloseDate > ?", 1.week.ago])             # CloseDate gt 2026-02-04T00:00:00Z
.where(["ListPrice >= ?", 500_000])               # ListPrice ge 500000
.where(["ListPrice >= ? and ListPrice <= ?", 300_000, 500_000])
```

Supported operators: `>`, `>=`, `<`, `<=`, `=`, `!=`

**Named placeholders:**

```ruby
.where(["ListPrice >= :min and ListPrice <= :max", min: 300_000, max: 500_000])
```

**Negation** — call `.where` with no arguments, then `.not`:

```ruby
.where.not(City: "Seattle")                       # City ne 'Seattle'
.where.not(StandardStatus: ['Closed', 'Expired']) # StandardStatus ne 'Closed' and ...
```

#### Value formatting

Ruby values are automatically formatted for OData:

| Ruby Type          | OData Output                       |
|--------------------|------------------------------------|
| `String`           | `'Seattle'` (single-quoted)        |
| `Integer`, `Float` | `500000` (bare)                    |
| `Time`, `DateTime` | `2026-02-04T12:00:00Z` (ISO 8601) |
| `Date`             | `2026-02-04`                       |
| `true` / `false`   | `true` / `false`                   |
| `nil`              | `null`                             |

#### Select, order, limit, offset

```ruby
client.properties
  .where(City: "Seattle")
  .select(:ListingKey, :City, :ListPrice)   # $select
  .order(ListPrice: :desc)                  # $orderby
  .limit(25)                                # $top
  .offset(50)                               # $skip
```

#### Includes (eager loading)

`.includes` maps to OData `$expand` for joining related resources:

```ruby
client.properties
  .where(City: "Seattle")
  .includes(:Media, :OpenHouses)
```

#### Default scope and unscoped

Properties automatically filter to `StandardStatus in ('Active','Pending')`:

```ruby
# Default applied
client.properties.where(City: "Seattle")
# → StandardStatus in ('Active','Pending') and City eq 'Seattle'

# Overridden when you specify StandardStatus
client.properties.where(StandardStatus: 'Closed')
# → StandardStatus eq 'Closed'

# Explicitly removed
client.properties.unscoped.where(City: "Seattle")
# → City eq 'Seattle'
```

No default scope is applied for members, offices, open_houses, or media.

#### Iteration and execution

Queries execute lazily — the API call fires when you access the results:

```ruby
listings = client.properties.where(City: "Seattle")
listings.each { |l| puts l["ListPrice"] }   # triggers API call
listings.length                               # uses cached results
listings[0]                                   # uses cached results
```

For large datasets, `.each` and `.find_each` auto-paginate through `@odata.nextLink`:

```ruby
client.properties.where(["ModificationTimestamp > ?", 1.day.ago]).each do |listing|
  process(listing)
end

client.properties.find_each(batch_size: 200) do |listing|
  process(listing)
end
```

#### Immutability

Each chainable method returns a new builder, so you can safely branch queries:

```ruby
base = client.properties.where(City: "Seattle")
active = base.where(StandardStatus: "Active")
closed = base.where(StandardStatus: "Closed")
# base, active, and closed are independent queries
```

---

### OData Queries (Direct)

The query builder above is the recommended way to query resources. You can also query resources directly using OData parameters. When called with arguments, the raw OData response hash is returned (you unwrap `value` yourself).

### Listing Requests

The simplest query is simply to call `properties` on the initialized client:

```ruby
client.properties(filter: "StandardStatus eq 'Active'")
```

The API will return a JSON response with an array of listing JSON objects.

### Getting a single listing

You can look up a single listing by sending a query with the listing's unique id (ListingKey).

```ruby
client.property('3yd-BINDER-5508272')
```

The response will be a single listing JSON object.

### Running queries

#### $filter

You can use `$filter` to send simple and complex queries to get a subset of listings depending on your particular use case.

To use `$filter`, pass it an expression in the format `FieldName operator Value`. For example, this query will return listings where the `StandardStatus` field equals (`eq`) the value `'Active'`:

```ruby
client.properties(filter: "StandardStatus eq 'Active'")
```

You can combine expressions together with or and and to perform more complex queries.

```ruby
client.properties(filter: "StandardStatus eq 'Active' and BrokerName eq 'Doe Brokerage'")
```
RESO Web API is built on the OData standard, but only requires compliant servers to support a subset of queries:

| Operator   | Description            | Example                                  |
|------------|------------------------|------------------------------------------|
|    `eq`    | Equals                 | `StandardStatus eq 'Active'`             |
|    `ne`    | Not equals             | `StandardStatus ne 'Active'`             |
|    `in`    | In                     | `StandardStatus in ('Active','Pending')` |
|    `ge`    | Greater than or equals | `ListPrice ge 100000`                    |
|    `gt`    | Greater than           | `ListPrice gt 100000`                    |
|    `le`    | Less than or equals    | `ListPrice le 100000`                    |
|    `lt`    | Less than              | `ListPrice lt 100000`                    |

Some older MLS systems does not support `in`.

#### $select

Instead of returning all of the listing fields in the response, you can use `$select` to only return specific fields you need.

```ruby
client.properties(select: "ListingKey")
client.properties(select: "ListingKey", filter: "StandardStatus eq 'Active'")
```

You can specify multiple fields to return by adding a "," between the fields in the `$select` parameter:

```ruby
client.properties(select: "ListingKey,StandardStatus")
```

#### $orderby

You can order the results by a field using `$orderby`:

```ruby
client.properties(orderby: "City desc")
```

#### $expand

$expand in OData is for joining additional resources. For the Syndication API this means you can bring in photos to any property query.

```ruby
client.properties(expand: "Media")
```

Different MLS systems support different resources to be included in an `$expand` statement. You can query for which resources the system you're integrating with supports:

```ruby
expandables = client.supported_expandables
client.properties(expand: expandables)
```

The `supported_expandables` method is a slow request, so you should store or cache the result of this method to speed up subsequent requests.

#### $ignorenulls

For servers that support it, `$ignorenulls` omits empty keys from the response to reduce data size.

```ruby
client.properties(ignorenulls: true)
```

#### $ignorecase

For servers that support it, `$ignorecase` performs case-insensitive filtering. Note that this is not a standard OData parameter and may only be supported by certain providers (e.g. Constellation1).

```ruby
client.members(filter: "MemberLastName eq 'Smith'", ignorecase: true)
```

#### Automatically iterate over all results

By passing a block to Media, Member, Office, and Property resource calls, subsequent paginated calls will automatically be made until the whole result set has been traversed. The block provided is executed for each returned object hash. The `batch` option can be used to return the full array of results.

Here are a couple of examples of how that can be used:

```ruby
client.properties(filter: "StandardStatus eq 'Active'") do |hash|
  puts "#{hash['ListingKey']} – #{hash['UnparsedAddress']}"
end

client.properties(filter: "StandardStatus eq 'Active'") do |hash|
  Listing.create(listing_key: hash['ListingKey'], data: hash)
end

client.properties(filter: "StandardStatus eq 'Active'", batch: true) do |results|
  Listing.insert_all(results) # Perform some batch operation
end
```


#### Manually iterate over all results

The default number of results returned is 100. You can override the default limit using the `$top` parameter. The higher the number specific for `$top`, the longer the API response will take, and pay attention to that different services does enforce a cap for number of records returned.

You can paginate through multiple sets of results using `$skip`, this can help you process multiple records quickly. In addition, if you use `$select` to target only certain fields, the API response time will be faster.

The following example API request will get the next 200 records starting at the 500th record:

```ruby
client.properties(select: "ListingKey", top: 200, skip: 500)
```

As you paginate through very large datasets, you might notice that the higher you set `$skip` the longer it takes for the API to return results. For those use cases, you should use `$skiptoken` to process very large datasets quickly.

#### Using $skiptoken for large datasets

`$skiptoken` can be used in combination with `$orderby` to process large datasets. To illustrate `$skiptoken`, we will use the following request to get 5 records ordered by `ListingKey`:

```ruby
client.properties(top: 5, orderby: "ListingKey")
```

An extract of the result could be:

```
{
    "@odata.context": "http://some.server.com/odata/$metadata#Property(ListingKey)",
    "value": [
      {
          "ListingKey": "3yd-AAABORMI-2813483"
      },
      {
          "ListingKey": "3yd-AAABORMI-2910696"
      },
      {
          "ListingKey": "3yd-AAABORMI-3101621"
      },
      {
          "ListingKey": "3yd-AAABORMI-3101967"
      },
      {
          "ListingKey": "3yd-AAABORMI-3200394"
      }
    ]
}
```

To get the next set of records, you would then use the value of the ListingKey field for the last record in the current set (3yd-AAABORMI-3200394) as your value for `$skiptoken`:

```ruby
client.properties(top: 5, orderby: "ListingKey", skiptoken: "3yd-AAABORMI-3200394")
```

`$skiptoken` allows you to process large datasets from the API in a sequence without sacrificing performance. The drawback is that you cannot "skip" to a random page, for that you must use the regular `$skip` parameter.

## Compatibility

This gem should work with any RESO Web API compliant service, but these are those that have been confirmed to work.

- [Constellation1](https://constellation1.com)
- [CoreLogic Trestle](https://trestle.corelogic.com)
- [ListHub](https://www.listhub.com)
- [Spark API](https://www.sparkapi.io)

If you use this gem to connect to another service or MLS, please submit a pull request with that service added in alphabetical order in this list.

## Acknowledgment

The inspiration for this gem and the outline and examples in this README is based on the [ListHub API][].

[ListHub API]: https://developer.listhub.com/api/

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/arcticleo/reso_api. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [Contributor Covenant](http://contributor-covenant.org) code of conduct.

## Code of Conduct

Everyone interacting in the RESO API project’s codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/arcticleo/reso_api/blob/master/CODE_OF_CONDUCT.md).
