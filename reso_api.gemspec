
lib = File.expand_path("../lib", __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "reso_api/version"

Gem::Specification.new do |spec|
  spec.name          = "reso_api"
  spec.version       = ResoApi::VERSION
  spec.authors       = ["Michael Edlund"]
  spec.email         = ["medlund@mac.com"]

  spec.summary       = %q{RESO Web API Wrapper}
  spec.description   = %q{Ruby wrapper for easy interaction with a RESO Web API compliant server.}
  spec.homepage      = "https://github.com/arcticleo/reso_api"

  spec.files         = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|spec|features)/})
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", ">= 2.3.15"
  spec.add_development_dependency "rake", ">= 12.3.3"
  spec.add_development_dependency "rspec", "~> 3.0"
  spec.add_dependency 'activesupport'
  spec.add_dependency "oauth2"
end
