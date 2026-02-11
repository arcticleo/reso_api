RSpec.describe RESO::API::QueryBuilder do
  let(:client) do
    RESO::API::Client.new(
      client_id: "client_id",
      client_secret: "client_secret",
      auth_url: "http://auth_url",
      base_url: "http://base_url"
    )
  end

  let(:client_with_osn) do
    RESO::API::Client.new(
      client_id: "client_id",
      client_secret: "client_secret",
      auth_url: "http://auth_url",
      base_url: "http://base_url",
      osn: "MyMLS"
    )
  end

  # --- QueryFormatter ---

  describe RESO::API::QueryFormatter do
    describe '.format_value' do
      it 'formats strings with single quotes' do
        expect(described_class.format_value("Seattle")).to eq("'Seattle'")
      end

      it 'escapes single quotes in strings' do
        expect(described_class.format_value("O'Brien")).to eq("'O''Brien'")
      end

      it 'formats integers as bare numbers' do
        expect(described_class.format_value(500_000)).to eq("500000")
      end

      it 'formats floats as bare numbers' do
        expect(described_class.format_value(99.5)).to eq("99.5")
      end

      it 'formats Time as ISO 8601 UTC' do
        time = Time.utc(2026, 2, 4, 12, 30, 0)
        expect(described_class.format_value(time)).to eq("2026-02-04T12:30:00Z")
      end

      it 'formats DateTime as ISO 8601 UTC' do
        dt = DateTime.new(2026, 2, 4, 12, 30, 0)
        expect(described_class.format_value(dt)).to eq("2026-02-04T12:30:00Z")
      end

      it 'formats Date as ISO 8601 date' do
        date = Date.new(2026, 2, 4)
        expect(described_class.format_value(date)).to eq("2026-02-04")
      end

      it 'formats true as bare boolean' do
        expect(described_class.format_value(true)).to eq("true")
      end

      it 'formats false as bare boolean' do
        expect(described_class.format_value(false)).to eq("false")
      end

      it 'formats nil as null' do
        expect(described_class.format_value(nil)).to eq("null")
      end
    end

    describe '.translate_operator' do
      {
        '>'  => 'gt',
        '>=' => 'ge',
        '<'  => 'lt',
        '<=' => 'le',
        '='  => 'eq',
        '!=' => 'ne'
      }.each do |ruby_op, odata_op|
        it "translates '#{ruby_op}' to '#{odata_op}'" do
          expect(described_class.translate_operator(ruby_op)).to eq(odata_op)
        end
      end

      it 'raises ArgumentError for unknown operators' do
        expect { described_class.translate_operator('??') }.to raise_error(ArgumentError)
      end
    end
  end

  # --- QueryConditions ---

  describe RESO::API::QueryConditions do
    describe '.parse' do
      context 'with hash conditions' do
        it 'generates eq for simple values' do
          result = described_class.parse({ City: "Seattle" })
          expect(result).to eq(["City eq 'Seattle'"])
        end

        it 'generates eq for integer values' do
          result = described_class.parse({ BedroomsTotal: 3 })
          expect(result).to eq(["BedroomsTotal eq 3"])
        end

        it 'generates in for array values' do
          result = described_class.parse({ StandardStatus: ['Active', 'Pending'] })
          expect(result).to eq(["StandardStatus in ('Active','Pending')"])
        end

        it 'generates ge/le for range values' do
          result = described_class.parse({ ListPrice: 300_000..500_000 })
          expect(result).to eq(["ListPrice ge 300000 and ListPrice le 500000"])
        end

        it 'generates ge only for endless range' do
          result = described_class.parse({ ListPrice: 300_000.. })
          expect(result).to eq(["ListPrice ge 300000"])
        end

        it 'generates le only for beginless range' do
          result = described_class.parse({ ListPrice: ..500_000 })
          expect(result).to eq(["ListPrice le 500000"])
        end

        it 'uses lt for exclusive end range' do
          result = described_class.parse({ ListPrice: 300_000...500_000 })
          expect(result).to eq(["ListPrice ge 300000 and ListPrice lt 500000"])
        end

        it 'handles multiple hash keys' do
          result = described_class.parse({ City: "Seattle", StandardStatus: "Active" })
          expect(result).to eq(["City eq 'Seattle'", "StandardStatus eq 'Active'"])
        end
      end

      context 'with string matching (% wildcards)' do
        it 'generates startswith for trailing %' do
          result = described_class.parse({ ListOfficeName: "Slifer%" })
          expect(result).to eq(["startswith(ListOfficeName,'Slifer')"])
        end

        it 'generates endswith for leading %' do
          result = described_class.parse({ ListOfficeName: "%Frampton" })
          expect(result).to eq(["endswith(ListOfficeName,'Frampton')"])
        end

        it 'generates contains for % on both ends' do
          result = described_class.parse({ ListOfficeName: "%Smith%" })
          expect(result).to eq(["contains(ListOfficeName,'Smith')"])
        end

        it 'treats plain strings as exact match' do
          result = described_class.parse({ City: "100% Pure" })
          expect(result).to eq(["City eq '100% Pure'"])
        end

        it 'escapes leading \\% as literal %' do
          result = described_class.parse({ City: "\\%Realty" })
          expect(result).to eq(["City eq '%Realty'"])
        end

        it 'escapes trailing \\% as literal %' do
          result = described_class.parse({ City: "Realty\\%" })
          expect(result).to eq(["City eq 'Realty%'"])
        end

        it 'handles startswith with escaped leading \\%' do
          result = described_class.parse({ City: "\\%Realty%" })
          expect(result).to eq(["startswith(City,'%Realty')"])
        end
      end

      context 'with array conditions (positional placeholders)' do
        it 'translates > operator' do
          result = described_class.parse(["CloseDate > ?", "2026-02-04"])
          expect(result).to eq(["CloseDate gt '2026-02-04'"])
        end

        it 'translates >= operator with integer' do
          result = described_class.parse(["ListPrice >= ?", 500_000])
          expect(result).to eq(["ListPrice ge 500000"])
        end

        it 'translates < operator' do
          result = described_class.parse(["ListPrice < ?", 1_000_000])
          expect(result).to eq(["ListPrice lt 1000000"])
        end

        it 'translates <= operator' do
          result = described_class.parse(["ListPrice <= ?", 1_000_000])
          expect(result).to eq(["ListPrice le 1000000"])
        end

        it 'translates = operator' do
          result = described_class.parse(["City = ?", "Seattle"])
          expect(result).to eq(["City eq 'Seattle'"])
        end

        it 'translates != operator' do
          result = described_class.parse(["City != ?", "Seattle"])
          expect(result).to eq(["City ne 'Seattle'"])
        end

        it 'handles multiple placeholders' do
          result = described_class.parse(["ListPrice >= ? and ListPrice <= ?", 300_000, 500_000])
          expect(result).to eq(["ListPrice ge 300000 and ListPrice le 500000"])
        end

        it 'handles Time values' do
          time = Time.utc(2026, 2, 4, 12, 0, 0)
          result = described_class.parse(["ModificationTimestamp > ?", time])
          expect(result).to eq(["ModificationTimestamp gt 2026-02-04T12:00:00Z"])
        end
      end

      context 'with array conditions (named placeholders)' do
        it 'substitutes named placeholders' do
          result = described_class.parse(["ListPrice >= :min and ListPrice <= :max", min: 300_000, max: 500_000])
          expect(result).to eq(["ListPrice ge 300000 and ListPrice le 500000"])
        end
      end

      context 'with negation' do
        it 'negates eq to ne' do
          result = described_class.parse({ City: "Seattle" }, negate: true)
          expect(result).to eq(["City ne 'Seattle'"])
        end

        it 'negates array values to individual ne conditions' do
          result = described_class.parse({ StandardStatus: ['Closed', 'Expired'] }, negate: true)
          expect(result).to eq(["StandardStatus ne 'Closed' and StandardStatus ne 'Expired'"])
        end

        it 'wraps array conditions with not()' do
          result = described_class.parse(["ListPrice > ?", 1_000_000], negate: true)
          expect(result).to eq(["not (ListPrice gt 1000000)"])
        end

        it 'negates contains with not' do
          result = described_class.parse({ City: "%Smith%" }, negate: true)
          expect(result).to eq(["not contains(City,'Smith')"])
        end

        it 'negates startswith with not' do
          result = described_class.parse({ City: "Sea%" }, negate: true)
          expect(result).to eq(["not startswith(City,'Sea')"])
        end

        it 'negates endswith with not' do
          result = described_class.parse({ City: "%tle" }, negate: true)
          expect(result).to eq(["not endswith(City,'tle')"])
        end
      end
    end
  end

  # --- WhereChain ---

  describe RESO::API::WhereChain do
    it 'adds negated conditions via .not' do
      builder = client.properties
      result = builder.where.not(City: "Seattle")
      expect(result).to be_a(RESO::API::QueryBuilder)

      filter = result.send(:build_filter)
      expect(filter).to include("City ne 'Seattle'")
    end
  end

  # --- QueryBuilder ---

  describe 'initialization' do
    it 'returns a QueryBuilder when called with no arguments' do
      expect(client.properties).to be_a(RESO::API::QueryBuilder)
    end

    it 'works for all filterable resources' do
      %i[properties members offices open_houses media].each do |resource|
        expect(client.send(resource)).to be_a(RESO::API::QueryBuilder)
      end
    end
  end

  describe 'backward compatibility' do
    it 'returns debug URL string when called with hash args' do
      result = client.properties(debug: true)
      expect(result).to be_a(String)
      expect(result).to include('/Property')
    end
  end

  describe '#where' do
    it 'adds hash conditions to the filter' do
      builder = client.properties.where(City: "Seattle")
      filter = builder.send(:build_filter)
      expect(filter).to include("City eq 'Seattle'")
    end

    it 'chains multiple where calls' do
      builder = client.properties
        .where(City: "Seattle")
        .where(["ListPrice >= ?", 500_000])
      filter = builder.send(:build_filter)
      expect(filter).to include("City eq 'Seattle'")
      expect(filter).to include("ListPrice ge 500000")
    end

    it 'supports array values for IN' do
      builder = client.properties.where(StandardStatus: ['Active', 'Pending'])
      filter = builder.send(:build_filter)
      expect(filter).to include("StandardStatus in ('Active','Pending')")
    end

    it 'supports range values' do
      builder = client.properties.where(ListPrice: 300_000..500_000)
      filter = builder.send(:build_filter)
      expect(filter).to include("ListPrice ge 300000 and ListPrice le 500000")
    end
  end

  describe '#where.not' do
    it 'negates equality conditions' do
      builder = client.properties.where.not(City: "Seattle")
      filter = builder.send(:build_filter)
      expect(filter).to include("City ne 'Seattle'")
    end

    it 'negates array conditions' do
      builder = client.properties.where.not(StandardStatus: ['Closed', 'Expired'])
      filter = builder.send(:build_filter)
      expect(filter).to include("StandardStatus ne 'Closed'")
      expect(filter).to include("StandardStatus ne 'Expired'")
    end

    it 'chains with regular where' do
      builder = client.properties
        .where(City: "Seattle")
        .where.not(StandardStatus: "Closed")
      filter = builder.send(:build_filter)
      expect(filter).to include("City eq 'Seattle'")
      expect(filter).to include("StandardStatus ne 'Closed'")
    end
  end

  describe '#select' do
    it 'sets $select fields' do
      builder = client.properties.where(City: "Seattle").select(:ListingKey, :City, :ListPrice)
      params = builder.send(:build_params)
      expect(params[:"$select"]).to eq("ListingKey,City,ListPrice")
    end
  end

  describe '#order' do
    it 'sets $orderby with hash syntax' do
      builder = client.properties.where(City: "Seattle").order(ListPrice: :desc)
      params = builder.send(:build_params)
      expect(params[:"$orderby"]).to eq("ListPrice desc")
    end

    it 'sets $orderby with string syntax' do
      builder = client.properties.where(City: "Seattle").order("ListPrice desc")
      params = builder.send(:build_params)
      expect(params[:"$orderby"]).to eq("ListPrice desc")
    end
  end

  describe '#limit' do
    it 'sets $top' do
      builder = client.properties.where(City: "Seattle").limit(25)
      params = builder.send(:build_params)
      expect(params[:"$top"]).to eq(25)
    end
  end

  describe '#offset' do
    it 'sets $skip' do
      builder = client.properties.where(City: "Seattle").offset(50)
      params = builder.send(:build_params)
      expect(params[:"$skip"]).to eq(50)
    end
  end

  describe '#includes' do
    it 'sets $expand' do
      builder = client.properties.where(City: "Seattle").includes(:Media, :OpenHouses)
      params = builder.send(:build_params)
      expect(params[:"$expand"]).to eq("Media,OpenHouses")
    end
  end

  describe 'default scope' do
    it 'adds StandardStatus default for properties' do
      builder = client.properties.where(City: "Seattle")
      filter = builder.send(:build_filter)
      expect(filter).to include("StandardStatus in ('Active','Pending')")
    end

    it 'does not add default when StandardStatus is specified' do
      builder = client.properties.where(StandardStatus: "Closed")
      filter = builder.send(:build_filter)
      expect(filter).to_not include("StandardStatus in ('Active','Pending')")
      expect(filter).to include("StandardStatus eq 'Closed'")
    end

    it 'does not add default when StandardStatus is in array condition' do
      builder = client.properties.where(["StandardStatus = ?", "Closed"])
      filter = builder.send(:build_filter)
      expect(filter).to_not include("StandardStatus in ('Active','Pending')")
    end

    it 'does not add default for non-property resources' do
      builder = client.members.where(MemberStatus: "Active")
      filter = builder.send(:build_filter)
      expect(filter).to_not include("StandardStatus")
    end

    it 'skips default when unscoped' do
      builder = client.properties.unscoped.where(City: "Seattle")
      filter = builder.send(:build_filter)
      expect(filter).to_not include("StandardStatus")
    end
  end

  describe 'OSN handling' do
    it 'prepends OSN filter when client has osn' do
      builder = client_with_osn.properties.where(City: "Seattle")
      filter = builder.send(:build_filter)
      expect(filter).to start_with("OriginatingSystemName eq 'MyMLS'")
    end

    it 'does not add OSN when client has no osn' do
      builder = client.properties.where(City: "Seattle")
      filter = builder.send(:build_filter)
      expect(filter).to_not include("OriginatingSystemName")
    end

    it 'does not duplicate OSN when already in conditions' do
      builder = client_with_osn.properties.where(OriginatingSystemName: "OtherMLS")
      filter = builder.send(:build_filter)
      expect(filter.scan("OriginatingSystemName").length).to eq(1)
    end
  end

  describe 'immutability (chaining returns new builder)' do
    it 'does not mutate the original builder' do
      base = client.properties.where(City: "Seattle")
      with_price = base.where(["ListPrice >= ?", 500_000])

      base_filter = base.send(:build_filter)
      price_filter = with_price.send(:build_filter)

      expect(base_filter).to_not include("ListPrice")
      expect(price_filter).to include("ListPrice ge 500000")
    end
  end
end
