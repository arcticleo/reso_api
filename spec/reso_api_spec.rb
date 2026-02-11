RSpec.describe RESO::API do
  it "has a version number" do
    expect(ResoApi::VERSION).not_to be nil
  end

  let(:client) do
    RESO::API::Client.new(
      client_id: "client_id",
      client_secret: "client_secret",
      auth_url: "http://auth_url",
      base_url: "http://base_url"
    )
  end

  let(:missing_client_id) do
    RESO::API::Client.new(
      client_secret: "client_secret",
      base_url: "http://base_url"
    )
  end

  let(:missing_client_secret) do
    RESO::API::Client.new(
      client_id: "client_id",
      base_url: "http://base_url"
    )
  end

  let(:missing_base_url) do
    RESO::API::Client.new(
      client_id: "client_id",
      client_secret: "client_secret"
    )
  end

  it "can initialize using client_id, client_secret, auth_url, base_url" do
    expect(client).to be_a(RESO::API::Client)
  end

  it "cannot initialize without client_id" do
    expect{missing_client_id}.to raise_error(RuntimeError)
  end

  it "cannot initialize without client_secret" do
    expect{missing_client_secret}.to raise_error(RuntimeError)
  end

  it "cannot initialize without base_url" do
    expect{missing_base_url}.to raise_error(RuntimeError)
  end

  %w(medium media member members office offices property properties).each do |method|
    it "instance has #{method} method" do
      expect(client.methods.include? method.to_sym).to be_truthy
    end
  end

  %w(media members offices properties).each do |call|
    %w(select skiptoken).each do |param|
      it "#{call} without #{param} does not add $#{param} to call" do
        expect(client.__send__(call, debug: true)).to_not include("$#{param}")
      end

      it "#{call} with #{param} adds $#{param} to call" do
        args = {debug: true}
        args[param.to_sym] = param
        expect(client.__send__(call, args)).to include("$#{param}")
      end
    end

    it "#{call} with filter adds $filter to call" do
      args = {debug: true, filter: "City eq 'Seattle'"}
      expect(client.__send__(call, args)).to include("$filter")
    end

    it "#{call} with top adds $top to call" do
      args = {debug: true, top: 10}
      expect(client.__send__(call, args)).to include("$top")
    end

    it "#{call} with skip adds $skip to call" do
      args = {debug: true, skip: 50}
      expect(client.__send__(call, args)).to include("$skip")
    end

    it "#{call} with orderby adds $orderby to call" do
      args = {debug: true, orderby: ["ListPrice desc"]}
      expect(client.__send__(call, args)).to include("$orderby")
    end
  end

end
