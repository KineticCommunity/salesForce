require File.expand_path(File.join(File.dirname(__FILE__), 'dependencies'))

class SalesforceTaskCreateV1
  def initialize(input)
    # Set the input document attribute
    @input_document = REXML::Document.new(input)
    
    # Store the info values in a Hash of info names to values.
    @info_values = {}
    REXML::XPath.each(@input_document,"/handler/infos/info") { |item|
      @info_values[item.attributes['name']] = item.text
    }
    
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
    # building up the task object
    task_object = {"Subject" => "#{@parameters['subject']}", "OwnerId" => "#{user_id}",
      "Status" => "Completed", "ActivityDate" => "#{DateTime.now.strftime('%Y-%m-%d')}"}

    if @parameters['opportunity_id'].to_s != ''
      task_object["WhatId"] = @parameters['opportunity_id']
    elsif @parameters['account_id'].to_s != ''
      task_object["WhatId"] = @parameters['account_id']
    end

    if @parameters['contact_id'].to_s != ''
      task_object['WhoId'] = @parameters['contact_id']
    end

    if @parameters['comment'].to_s != ''
      task_object['description'] = @parameters['comment']
    end
      
    task_object = task_object.to_json
    begin
      resp = RestClient.post("https://#{@info_values['salesforce_instance']}.salesforce.com/services/data/v20.0/sobjects/Task",
        task_object, :content_type => "application/json", :accept => :json, :authorization => "OAuth #{access_token}")
    rescue RestClient::BadRequest => error
      error_json = JSON.parse(error.http_body)
      raise StandardError, error_json[0]['message'].to_s
    end
    "<results/>"
  end

  def authorize()
    # Setting up the hash map that will be turned into json and passed to
    # Salesforce to authenticate
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
    # Getting the salesforce id of the user according to their email address.
    # This will then be passed in the task body so that the task will be
    # assigned to that user.
    url = "https://#{@info_values['salesforce_instance']}.salesforce.com/services/data/v20.0/query?q=SELECT%20Id%20from%20User%20WHERE%20Email='#{@parameters['requester_email']}'"
    begin 
      resp = RestClient.get(url, :content_type => "application/x-www-form-urlencoded", :accept => :json, :authorization => "OAuth #{access_token}")
      json_resp = JSON.parse(resp)
      begin 
        id = json_resp['records'][0]['Id']
      rescue Exception => e
        raise StandardError, "Invalid Request: Requester Email does not exist"
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
