require "rails_helper"

RSpec.describe "check link path", type: :request do
  let(:link) { "http://www.example.com" }

  def check_link_path(query_params = {})
    path = "/check-link"
    path + (query_params.empty? ? "?#{query_params.to_query}" : "")
  end

  def build_link_report(params)
    {
      "uri"       => params.fetch(:uri, anything),
      "status"    => params.fetch(:status, anything),
      "checked"   => params.fetch(:checked, anything),
      "errors"    => params.fetch(:errors, []),
      "warnings"  => params.fetch(:warnigns, []),
    }
  end

  shared_examples "returns link report" do
    it "returns 200" do
      expect(response).to have_http_status(200)
    end

    it "returns a link report" do
      json = JSON.parse(response.body)
      expect(json).to match(link_report)
    end
  end

  context "when no uri is requested" do
    before do
      get "/check-link"
    end

    it "returns 400" do
      expect(response).to have_http_status(400)
    end
  end

  context "when an ok checked uri is requested" do
    let(:link_report) { build_link_report(uri: link, status: "ok") }

    before do
      # create db entries
      get check_link_path(uri: link)
    end

    include_examples "returns link report"
  end

  context "when an unchecked uri is requested" do
    let(:link_report) { build_link_report(uri: link, status: "pending") }

    before { get check_link_path(uri: link) }

    include_examples "returns link report"
  end

  context "when a checked uri, that is of status caution, is requested" do
    let(:warnings) do
      {
        "risky_tld" => ["Potentially suspicious top level domain."],
      }
    end
    let(:link_report) { build_link_report(uri: link, status: "caution", warnings: warnings) }

    before do
      # create db entries
      get check_link_path(uri: link)
    end

    include_examples "returns link report"
  end

  context "when a checked uri, that is of status broken, is requested" do
    let(:errors) do
      {
        "cyclic_redirect" => ["Has a cyclic redirect."],
      }
    end
    let(:link_report) { build_link_report(uri: link, status: "broken", errors: errors) }

    before do
      # create db entries
      get check_link_path(uri: link)
    end

    include_examples "returns link report"
  end

  context "when a checked uri was checked outside the `content-within` time" do
    let(:link_report) { build_link_report(uri: link, status: "pending") }

    before do
      # create db entries
      get check_link_path(uri: link, "checked-within": 5.minutes.to_i)
    end

    include_examples "returns link report"
  end

  context "when an unchecked uri is requested with synchronous = true" do
    let(:link) { "http://www.example.com/page" }
    let(:link_report) { build_link_report(uri: link, status: "pending") }

    before do
      stub_request(:head, link).to_return(status: 200)
      get check_link_path(uri: link, "synchronous": "true")
    end

    include_examples "returns link report"
  end
end
