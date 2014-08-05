#!/usr/bin/ruby
require 'net/https'
require 'uri'
require 'time'
require 'json'
require 'yaml'
require 'optparse'

class LbCal

    def initialize

        config = YAML.load_file(File.join(__dir__, 'config.yaml'))

        @client_id = config['client_id']
        @client_secret = config['client_secret']
        @device_code = ""

        @cal_id = config['cal_id']

        @access_token = config['access_token']
        @refresh_token = config['refresh_token']

        @work_cal_api = config['work_cal_api']
        @work_email = config['work_email']
        @cal_query = config['cal_query']

    end

    def saveTokens(a,r)

        config = YAML.load_file('config.yml')
        config['access_token'] = a
        config['refresh_token'] = r

        File.open('config.yml', 'w') do |f|
            YAML.dump(config, f)
        end

    end

    def getAuth
        uri = URI.parse("https://accounts.google.com/o/oauth2/device/code")

        data = {
            "client_id" => @client_id,
            "scope" => "https://www.googleapis.com/auth/calendar"

        }

        h = Net::HTTP.new(uri.host, uri.port)
        h.use_ssl = true
        req = Net::HTTP::Post.new(uri.path)
        req.set_form_data(data)

        res = h.request(req)


        d = JSON.parse( res.body)
        @device_code = d["device_code"]
        puts "Go here: #{d['verification_url']}"
        puts "Enter this code: #{d['user_code']}"
        puts "After authorizing, hit Enter"

        g = $stdin.gets

        self.getTokens
    end

    def getTokens
        uri = URI.parse("https://accounts.google.com/o/oauth2/token")

        data = {
                "client_id" => @client_id,
                "client_secret" => @client_secret,
                "code" => @device_code,
                "grant_type" => "http://oauth.net/grant_type/device/1.0"
        }


        h = Net::HTTP.new(uri.host, uri.port)
        h.use_ssl = true
        req = Net::HTTP::Post.new(uri.path)
        req.set_form_data(data)

        res = h.request(req)


        d = JSON.parse( res.body)
        # p d

        @access_token = d['access_token']
        @refresh_token = d['refresh_token']

        self.saveTokens(@access_token,@refresh_token)
    end

  	def refreshToken
        uri = URI.parse("https://accounts.google.com/o/oauth2/token")

        data = {
                "client_id" => @client_id,
                "client_secret" => @client_secret,
                "refresh_token" => @refresh_token,
                "grant_type" => "refresh_token"
        }


        h = Net::HTTP.new(uri.host, uri.port)
        h.use_ssl = true
        req = Net::HTTP::Post.new(uri.path)
        req.set_form_data(data)

        res = h.request(req)


        d = JSON.parse( res.body)
        
        # puts "refreshing token"
        # puts "ref: #{res.code}"

        @access_token = d['access_token']

        self.saveTokens(@access_token,@refresh_token)

    end

    def apiCall(url, method, data)
 	
        uri = URI.parse(url)
		
		h = Net::HTTP.new(uri.host, uri.port)
        h.use_ssl = true

      	case method
          	when "get"

          		data['access_token'] = @access_token
     			uri.query = URI.encode_www_form( data )
    	       	req = Net::HTTP::Get.new uri.request_uri

          	when "post"

          		params = {"access_token" => @access_token}
     			uri.query = URI.encode_www_form( params )
    	       	req = Net::HTTP::Post.new uri.request_uri
    	       	req.body = JSON.generate(data)
    	       	req.add_field("content-type","application/json")

          	when "delete"    

          		params = {"access_token" => @access_token}
     			uri.query = URI.encode_www_form( params )
    	       	req = Net::HTTP::Delete.new uri.request_uri

        end

        res = h.request(req)
        
        #p res.code
        #p res.body

        case res.code
            when "200"
            	d = JSON.parse( res.body)
            when "401"
    			self.refreshToken
            	d = self.apiCall(url,method,data)
            else
            	d = res
        end

        return d
    
    end

    def getOld()

    	data = {

			q: @cal_query,
			orderBy: "startTime",
			singleEvents: "true",
			timeMin: Time.new.xmlschema
		}
		url = "https://www.googleapis.com/calendar/v3/calendars/#{@cal_id}/events"
		res = self.apiCall(url,"get",data);

		return res['items']

    end

    def deleteOld(eid)
    	# puts "delete: #{eid}"
    	url = "https://www.googleapis.com/calendar/v3/calendars/#{@cal_id}/events/#{eid}"
    	res = self.apiCall(url,"delete",{});

    	# p res
    end 


    def createEvent(title,startDate,endDate)

    	data = {

    		"summary" => title,
    		"description" => "lbclass",
    		"start" => {"date"=>startDate},
    		"end" => {"date"=>endDate},
    		"reminders" => {"useDefault"=>"false"}
    	}

		url = "https://www.googleapis.com/calendar/v3/calendars/#{@cal_id}/events"
    	res = self.apiCall(url,"post",data);
    	
    end


    def createEvents(items)
        puts "> creating entries"
    	items.each do |i|

    		title = self.eventFormat(i)
    		startDate = Date.parse(i['start'])
    		endDate = Date.parse(i['end'])+1

    		self.createEvent(title,startDate,endDate)
           
    	end

    end



    def lbSchedule()

        uri = URI.parse(@work_cal_api)
        data = {
            "method"=>"userCalendar",
            "email"=>@work_email
        }

        puts "> get sched"

        h = Net::HTTP.new(uri.host, uri.port)
        req = Net::HTTP::Post.new(uri.path)
        req.set_form_data(data)
 
        res = h.request(req)

        d =  JSON.parse(res.body)

    end


    def eventFormat(sch)

        cnt = sch['cnt'].to_i

        crstitle = sch['gcal_title'].split(" - ")

        t = "[#{cnt}]#{crstitle[0]}"

        if sch['loc'] != "Austin, TX"
        t = "#{t}/#{sch['loc']}"
        end

        return t
    end

end


g = LbCal.new

if ARGV[0] == "setup"
    LbCal.new.getAuth()
else
	#===Remove Old
	old = g.getOld()
	if old
		old.each do |i|
			 g.deleteOld(i['id'])
		end
	end
	#===Put Latest
	sch = g.lbSchedule()
	if sch.length != 0
		g.createEvents(sch)
	end
end


