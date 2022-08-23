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

To set up an API client and access a service, you need three pieces of information:

- Client ID
- Client Secret
- Base API endpoint
- Authentication URL

You'll recognize the base API endpoint by it ending with /odata, and the authentication URL by it likely ending with /token.

You pass these four pieces of information to create an instance of an API client:

```ruby
client = RESO::API::Client.new(client_id: client_id, client_secret: client_secret, auth_url: auth_url, base_url: base_url)
```

When calling API endpoints using the initialized client, it will automatically fetch and manage access and authentication tokens transparently in the background.

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

### Listing Requests

The simplest query is simply to call `properties` on the initialized client: 

```ruby
client.properties
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

| Operator   | Description            | Example                      |
|------------|------------------------|------------------------------|
|    `eq`    | Equals                 | `StandardStatus eq 'Active'` |
|    `ne`    | Not equals             | `StandardStatus ne 'Active'` |
|    `ge`    | Greater than or equals | `ListPrice ge 100000`        |
|    `gt`    | Greater than           | `ListPrice gt 100000`        |
|    `le`    | Less than or equals    | `ListPrice le 100000`        |
|    `lt`    | Less than              | `ListPrice lt 100000`        |

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

$expand in oData is meant to join two resources together. For the Syndication API this means you can bring in photos to any property query.

```ruby
client.properties(expand: "Media")
```

#### $ignorenulls

For servers that support it, `$ignorenulls` omits empty keys from the response to reduce data size.

```ruby
client.properties(ignorenulls: "true")
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
