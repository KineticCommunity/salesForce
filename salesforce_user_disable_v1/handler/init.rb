require File.expand_path(File.join(File.dirname(__FILE__), 'dependencies'))

class SalesforceUserDisableV1
  def initialize(input)
    # Set the input document attribute
    @input_document = REXML::Document.new(input)
    
    # Store the info values in a Hash of info names to values.
    @info_values = {}
    REXML::XPath.each(@input_document,"/handler/infos/info") { |item|
      @info_values[item.attributes['name']] = item.text
    }
    @enable_debug_logging = @info_values['enable_debug_logging'] == 'Yes'
    
    # Retrieve all of the handler parameters and store them in a hash attribute
    # named @parameters.
    @parameters = {}
    REXML::XPath.match(@input_document, 'handler/parameters/parameter').each do |node|
      @parameters[node.attribute('name').value] = node.text.to_s
    end
  end
  
  def execute()
    access_token = authorize()
    user_id = get_user_id(access_token)

    puts "Making the update call to deactivate #{@parameters['username']}" if @enable_debug_logging
    begin
      resp = RestClient.patch("https://#{@info_values['salesforce_instance']}.salesforce.com/services/data/v28.0/sobjects/User/#{user_id}",
        {"IsActive" => "false"}.to_json, :content_type => "application/json", :accept => :json, :authorization => "OAuth #{access_token}")
    rescue RestClient::BadRequest => error
      error_json = JSON.parse(error.http_body)
      raise StandardError, error_json[0]['message'].to_s
    end

    "<results/>"
  end

  def authorize()
    # Setting up the hash map that will be turned into json and passed to
    # Salesforce to authenticate
    puts "Authenticating with Salesforce to retrieve an access token" if @enable_debug_logging
    params = {:username => @info_values['username'],
              :password => @info_values['password']+@info_values['security_token'],
              :client_id => @info_values['client_id'],
              :client_secret => @info_values['client_secret'],
              :grant_type => "password"}
    begin
      resp = RestClient.post "https://login.salesforce.com/services/oauth2/token",params, :content_type => "application/x-www-form-urlencoded", :accept => :json
      json_resp = JSON.parse(resp)
      access_token = json_resp['access_token']
    rescue RestClient::BadRequest => error
      error_json = JSON.parse(error.http_body)
      raise StandardError, error_json['error_description'].to_s
    end

    return access_token
  end

  def get_user_id(access_token)
    # Getting the salesforce id of the user according to their username.
    # This will then be used to deactive the desired account.
    puts "Querying Salesforce to get the user id for #{@parameters['username']}" if @enable_debug_logging
    url = "https://#{@info_values['salesforce_instance']}.salesforce.com/services/data/v28.0/query?q=SELECT%20Id%20from%20User%20WHERE%20Username='#{@parameters['username']}'"
    begin 
      resp = RestClient.get(url, :content_type => "application/x-www-form-urlencoded", :accept => :json, :authorization => "OAuth #{access_token}")
      json_resp = JSON.parse(resp)
      begin 
        id = json_resp['records'][0]['Id']
      rescue Exception => e
        raise StandardError, "Invalid Request: Username does not exist"
      end
    rescue RestClient::BadRequest => error
      error_json = JSON.parse(error.http_body)
      raise StandardError, error_json['error_description'].to_s
    end

    return id
  end

  # This is a template method that is used to escape results values (returned in
  # execute) that would cause the XML to be invalid.  This method is not
  # necessary if values do not contain character that have special meaning in
  # XML (&, ", <, and >), however it is a good practice to use it for all return
  # variable results in case the value could include one of those characters in
  # the future.  This method can be copied and reused between handlers.
  def escape(string)
    # Globally replace characters based on the ESCAPE_CHARACTERS constant
    string.to_s.gsub(/[&"><]/) { |special| ESCAPE_CHARACTERS[special] } if string
  end
  # This is a ruby constant that is used by the escape method
  ESCAPE_CHARACTERS = {'&'=>'&amp;', '>'=>'&gt;', '<'=>'&lt;', '"' => '&quot;'}
end
