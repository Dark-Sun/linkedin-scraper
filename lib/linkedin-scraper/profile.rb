# -*- encoding: utf-8 -*-

module Linkedin
  class Profile
    ATTRIBUTES = %w(
      awards
      name
      first_name
      last_name
      title
      location
      number_of_connections
      country
      industry
      summary
      picture
      projects
      linkedin_url
      education
      groups
      websites
      languages
      skills
      certifications
      organizations
      past_companies
      current_companies
      recommended_visitors )

    attr_reader :page, :linkedin_url

    def initialize(url, options = {})
      @linkedin_url = url
      @options = options
      @page = http_client.get(url)
      pp @page
    end

    def awards
      if @page.at('#awards')
        @awards ||= get_awards
      end
    end

    def name
      "#{first_name} #{last_name}"
    end

    def first_name
      @first_name ||= (@page.at('.fn').text.split(' ', 2)[0].strip if @page.at('.fn'))
    end

    def last_name
      @last_name ||= (@page.at('.fn').text.split(' ', 2)[1].strip if @page.at('.fn'))
    end

    def title
      @title ||= (@page.at('.title').text.gsub(/\s+/, ' ').strip if @page.at('.title'))
    end

    def location
      @location ||= (@page.at('.locality').text.split(',').first.strip if @page.at('.locality'))
    end

    def country
      @country ||= (@page.at('.locality').text.split(',').last.strip if @page.at('.locality'))
    end

    def number_of_connections
      if @page.at('.member-connections')
        @connections ||= (@page.at('.member-connections').text.match(/[0-9]+[\+]{0,1}/)[0])
      end
    end

    def industry
      if @page.at('#demographics .descriptor')
        @industry ||= (@page.search('#demographics .descriptor')[-1].text.gsub(/\s+/, ' ').strip)
      end
    end

    def summary
      @summary ||= (@page.at('#summary .description').text.gsub(/\s+/, ' ').strip if @page.at('#summary .description'))
    end

    def picture
      if @page.at('.profile-picture img')
        @picture ||= @page.at('.profile-picture img').attributes.values_at('src', 'data-delayed-url').
            compact.first.value.strip
      end
    end

    def skills
      @skills ||= (@page.search('.pills .skill:not(.see-less):not(.see-more)').map { |skill| skill.text.strip if skill.text } rescue nil)
    end

    def past_companies
      @past_companies ||= get_companies.reject { |c| c[:end_date] == 'Present' }
    end

    def current_companies
      @current_companies ||= get_companies.find_all { |c| c[:end_date] == 'Present' }
    end

    def education
      @education ||= @page.search('.schools .school').map do |item|
        name = item.at('h4').text.gsub(/\s+|\n/, ' ').strip if item.at('h4')
        desc = item.search('h5 > span')[0].text.gsub(/\s+|\n/, ' ').strip if item.search('h5').last
        if item.search('h5').last.at('.degree')
          degree = item.search('h5').last.at('.degree').text.gsub(/\s+|\n/, ' ').strip.gsub(/,$/, '')
        end
        major = item.search('h5').last.at('.major').text.gsub(/\s+|\n/, ' ').strip if item.search('h5').last.at('.major')
        period = item.at('.date-range').text.gsub(/\s+|\n/, ' ').strip if item.at('.date-range')
        start_date, end_date = item.at('.date-range').text.gsub(/\s+|\n/, ' ').strip.split(' – ') rescue nil

        {
            name: name,
            description: desc,
            degree: degree,
            major: major,
            period: period,
            start_date: start_date,
            end_date: end_date
        }
      end
    end

    def websites
      @websites ||= @page.search('.websites li').flat_map do |site|
        url = site.at('a')['href']
        CGI.parse(URI.parse(url).query)['url']
      end
    end

    def groups
      @groups ||= @page.search('#groups .group .item-title').map do |item|
        name = item.text.gsub(/\s+|\n/, ' ').strip
        link = item.at('a')['href']

        { name: name, link: link }
      end
    end

    def organizations
      @organizations ||= @page.search('#background-organizations .section-item').map do |item|
        name = item.at('.summary').text.gsub(/\s+|\n/, ' ').strip rescue nil
        start_date, end_date = item.at('.organizations-date').text.gsub(/\s+|\n/, ' ').strip.split(' – ') rescue nil
        start_date = Date.parse(start_date) rescue nil
        end_date = Date.parse(end_date) rescue nil
        {name: name, start_date: start_date, end_date: end_date}
      end
    end

    def languages
      @languages ||= @page.search('#languages ul li').map do |item|
        language = item.search('h4').text rescue nil
        proficiency = item.search('p.proficiency').text.gsub(/\s+|\n/, ' ').strip rescue nil
        { language: language, proficiency: proficiency }
      end
    end

    def certifications
      @certifications ||= @page.search('#certifications ul li').map do |item|
        name = item.at('h4').text.gsub(/\s+|\n/, ' ').strip rescue nil
        authority_with_license = item.at('h5').text.gsub(/\s+|\n/, ' ').strip rescue nil
        authority, license = authority_with_license.split(/,\sLicense\s/) rescue nil
        start_date = item.at('time').text.gsub(/\s+|\n/, ' ').strip rescue nil
        { name: name, authority: authority, license: license, start_date: start_date }
      end
    end


    def recommended_visitors
      @recommended_visitors ||= @page.search('.insights .browse-map/ul/li.profile-card').map do |node|
        visitor = {}
        visitor[:link] = node.at('a')['href']
        visitor[:name] = node.at('h4/a').text
        if node.at('.headline')
          visitor[:title], visitor[:company], _ = node.at('.headline').text.gsub('...', ' ').split(' at ')
        end
        visitor
      end
    end

    def projects
      @projects = []

      @page.search('#projects > ul > .project').each do |node|
        begin
          project = {}

          project[:title]      = node.search('.item-title > a')&.text
          project[:start_date] = Date.parse(node.search(".date-range > time")[0]&.text) rescue nil
          project[:end_date]   = Date.parse(node.search(".date-range > time")[1]&.text) rescue nil
          project[:end_date]  ||= "Present"
          project[:description] = node.search('.description')&.text

          @projects << project
        rescue => e
          puts e
        end
      end

      @projects
    end

    def to_json
      require 'json'
      ATTRIBUTES.reduce({}) { |hash, attr| hash[attr.to_sym] = self.send(attr.to_sym); hash }.to_json
    end

    private
    def get_awards
      if @awards
        return @awards
      else
        @awards = []
      end

      @page.search('#awards .award').each do |node|
        award = {}
        award[:title] = node.at('.item-title').text.gsub(/\s+|\n/, ' ').strip if node.at('.item-title')
        award[:description] = node.at('.description').text.gsub(/\s+|\n/, ' ').strip if node.at('.description')
        @awards << award
      end

      @awards
    end

    def get_companies
      if @companies
        return @companies
      else
        @companies = []
      end

      @page.search("#experience > ul > .position").each do |node|
        title = node.search(".item-title")&.text

        next if title.empty?

        company_name     = node.search(".item-subtitle")&.text

        start_date       = Date.parse(node.search(".date-range > time")[0]&.text) rescue nil
        start_date     ||= Date.strptime(node.search(".date-range > time")[0]&.text, '%Y') rescue nil

        end_date         = Date.parse(node.search(".date-range > time")[1]&.text) rescue nil
        end_date       ||= Date.strptime(node.search(".date-range > time")[1]&.text, '%Y') rescue nil
        end_date       ||= "Present" if start_date

        description = node.search(".description")&.text

        company = {}
        company[:title] = title
        company[:company] = company_name
        company[:location] = ""
        company[:start_date] = start_date
        company[:end_date]   = end_date
        company[:description] = description

        @companies << company
      end

      @companies
    end

    def parse_date(date)
      date = '#{date}-01-01' if date =~ /^(19|20)\d{2}$/
      Date.parse(date)
    end

    def get_company_details(link)
      sleep(1.5)
      parsed = URI::parse(get_linkedin_company_url(link))
      parsed.fragment = parsed.query = nil
      result = { linkedin_company_url: parsed.to_s }

      page = http_client.get(parsed.to_s)
      company_details = JSON.parse(page.at('#stream-footer-embed-id-content').children.first.text) rescue nil
      if company_details
        result[:website] = company_details['website']
        result[:description] = company_details['description']
        result[:company_size] = company_details['size']
        result[:type] = company_details['companyType']
        result[:industry] = company_details['industry']
        result[:founded] = company_details['yearFounded']
        headquarters = company_details['headquarters']
        if headquarters
          result[:address] = %{#{headquarters['street1']} #{headquarters['street2']} #{headquarters['city']}, #{headquarters['state']} #{headquarters['zip']} #{headquarters['country']}}
          [:street1, :street2, :city, :zip, :state, :country].each do |section|
            result[section] = headquarters[section.to_s]
          end
        end
      end
      result
    end

    def http_client

      @http_client ||= Mechanize.new do |agent|
        agent.user_agent = Linkedin::UserAgent.randomize
        if !@options.empty?
          agent.set_proxy(@options[:proxy_ip], @options[:proxy_port], @options[:username], @options[:password])
          agent.agent.set_socks(@options[:socks_host], @options[:socks_port])
          agent.open_timeout = @options[:open_timeout]
          agent.read_timeout = @options[:read_timeout]
          agent.max_history = 0
        end
      end

    end

    def get_linkedin_company_url(link)
      http = %r{http://www.linkedin.com/}
      https = %r{https://www.linkedin.com/}
      if http.match(link) || https.match(link)
        link
      else
        "http://www.linkedin.com/#{link}"
      end
    end
  end
end
