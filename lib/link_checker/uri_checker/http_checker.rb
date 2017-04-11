module LinkChecker::UriChecker
  class HttpChecker
    INVALID_TOP_LEVEL_DOMAINS = %w(xxx adult dating porn sex sexy singles).freeze
    REDIRECT_STATUS_CODES = [301, 302, 303, 307, 308].freeze
    REDIRECT_LIMIT = 8
    REDIRECT_WARNING = 2
    RESPONSE_TIME_LIMIT = 15
    RESPONSE_TIME_WARNING = 2.5

    attr_reader :uri, :redirect_history, :report

    def initialize(uri, redirect_history: [])
      @uri = uri
      @redirect_history = redirect_history
      @report = Report.new
    end

    def call
      if uri.host.nil?
        report.add_error(:no_host, "No host given", "Your link has no hostname.")
        return report
      end

      check_redirects
      check_top_level_domain
      check_credentials

      head_response = check_head_request
      return report if report.has_errors?

      check_get_request if head_response && head_response.headers["Content-Type"] == "text/html"
      return report if report.has_errors?

      check_google_safebrowsing

      report
    end

  private

    def check_redirects
      report.add_error(:too_many_redirects, "Too many redirects", "Your link has a large number of redirects.") if redirect_history.length >= REDIRECT_LIMIT
      report.add_error(:cyclic_redirects, "Has a cyclic redirect", "Your link has a cyclic redirect.") if redirect_history.include?(uri)
      report.add_warning(:multiple_redirects, "Multiple redirects", "Your link has many redirects.") if redirect_history.length == REDIRECT_WARNING
    end

    def check_top_level_domain
      tld = uri.host.split(".").last
      if INVALID_TOP_LEVEL_DOMAINS.include?(tld)
        report.add_warning(:risky_tld, "Risky TLD", "Potentially suspicious top level domain (#{tld}).")
      end
    end

    def check_credentials
      if uri.user.present? || uri.password.present?
        report.add_warning(:credentials_in_uri, "Credentials in URI", "There are credentials in the URL.")
      end
    end

    def check_head_request
      start_time = Time.now
      response = make_request(:head)
      end_time = Time.now
      response_time = end_time - start_time

      report.add_warning(:slow_response, "Slow response time", "This page may take a long time to load.") if response_time > RESPONSE_TIME_WARNING

      return response if report.has_errors?

      if response.status >= 400 && response.status < 500
        report.add_error(:http_client_error, "Received 4xx response", "This page may not open properly.")
      elsif response.status >= 500 && response.status < 600
        report.add_error(:http_server_error, "Received 5xx response", "This page may not open properly.")
      else
        unless response.status == 200 || REDIRECT_STATUS_CODES.include?(response.status)
          report.add_warning(:http_non_200, "Non 200 response", "Received a non 200 success response.")
        end
      end

      response
    end

    def check_get_request
      response = make_request(:get)
      return unless response

      page = Nokogiri::HTML(response.body)
      rating = page.css("meta[name=rating]").first&.attr("value")
      if %w(restricted mature).include?(rating)
        report.add_warning(:meta_rating, "Mature Rating", "Page suggests it contains mature content.")
      end
    end

    def check_google_safebrowsing
      api_key = Rails.application.secrets.google_api_key
      return unless api_key

      response = Faraday.post do |req|
        req.url "https://safebrowsing.googleapis.com/v4/threatMatches:find?key=#{api_key}"
        req.headers["Content-Type"] = "application/json"
        req.body = {
          client: {
            clientId: "gds-link-checker", clientVersion: "0.1.0"
          },
          threatInfo: {
            threatTypes: %w(THREAT_TYPE_UNSPECIFIED MALWARE SOCIAL_ENGINEERING UNWANTED_SOFTWARE POTENTIALLY_HARMFUL_APPLICATION),
            platformTypes: %w(ANY_PLATFORM),
            threatEntryTypes: %w(URL),
            threatEntries: [{ url: uri.to_s }]
          }
        }.to_json
      end

      if response.status == 200
        data = JSON.parse(response.body)
        if data.include?("matches") && data["matches"]
          report.add_warning(:google_safebrowsing, "Possible threat", "Google Safebrowsing has detected a threat.")
        end
      else
        Airbrake.notify(
          "Unable to talk to Google Safebrowsing API!",
          status: response.status,
          body: response.body,
          headers: response.headers,
        )
      end
    end

    def make_request(method)
      begin
        response = run_connection_request(method)

        if REDIRECT_STATUS_CODES.include?(response.status) && response.headers.include?("location") && !report.has_errors?
          target_uri = uri + response.headers["location"]
          subreport = ValidUri
            .new(redirect_history: redirect_history + [uri])
            .call(target_uri.to_s)
          report.merge(subreport)
        end

        response
      rescue Faraday::ConnectionFailed
        report.add_error(:cant_connect, "Connection failed", "Cannot connect to the server.")
      rescue Faraday::TimeoutError
        report.add_error(:timeout, "Timeout Error", "The server timed out.")
      rescue Faraday::SSLError
        report.add_error(:ssl_configuration, "SSL Error", "The server is not secure.")
      rescue Faraday::Error => e
        report.add_error(:unknown_http_error, e.class.to_s, e.message)
      end
    end

    def run_connection_request(method)
      connection.run_request(method, uri, nil, nil) do |request|
        request.options[:timeout] = RESPONSE_TIME_LIMIT
        request.options[:open_timeout] = RESPONSE_TIME_LIMIT
      end
    end

    def connection
      @connection ||= Faraday.new(headers: { accept_encoding: "none" }) do |faraday|
        faraday.adapter Faraday.default_adapter
      end
    end
  end
end
