# RESO API

Ruby wrapper for easy interaction with a RESO Web API compliant server.

This document does not documentation for the RESO Web API. More information about the RESO Web API standard can be found on [RESO][].

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

You pass these three pieces of information when creating an instance of an API client:

```ruby
client = RESO::API::Client.new(client_id: client_id, client_secret: client_secret, base_url: base_url)
```

When calling API endpoints, the initialized client will automatically fetch and manage access and authentication tokens in the background.

### Resources

This API wrapper currently only supports the Property resource. Support for missing standard resources is planned:

- Media
- Member
- Office

### Retrieving Metadata

You can get the metadata for the Property resource using:

```ruby
client.metadata
```

The response will be an EDMX xml schema document that matches the [RESO Data Dictionary standard][].

[RESO Data Dictionary standard]: https://www.reso.org/data-dictionary/

### Listing Requests

To query for listings via the Syndication API: 

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
client.properties(filter: "StandardStatus eq 'Active' and CustomBrokerName eq 'Doe Brokerage'")
```

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

#### Pagination, $top, and $skip

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

$skiptoken allows you to process large datasets from the API in a sequence without sacrificing performance. The drawback is that you cannot "skip" to a random page, for that you must use the regular `$skip` parameter.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/[USERNAME]/reso_api. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [Contributor Covenant](http://contributor-covenant.org) code of conduct.

## Code of Conduct

Everyone interacting in the ResoApi project’s codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/[USERNAME]/reso_api/blob/master/CODE_OF_CONDUCT.md).
