# Require the dependencies file to load the vendor libraries
require File.expand_path(File.join(File.dirname(__FILE__), "dependencies"))

class SalesforceAttachmentUploadV1
  # Prepare for execution by building Hash objects for necessary values and
  # validating the present state.  This method sets the following instance
  # variables:
  # * @input_document - A REXML::Document object that represents the input Xml.
  # * @info_values - A Hash of info names to info values.
  # * @parameters - A Hash of parameter names to parameter values.
  #
  # This is a required method that is automatically called by the Kinetic Task
  # Engine.
  #
  # ==== Parameters
  # * +input+ - The String of Xml that was built by evaluating the node.xml
  #   handler template.
  def initialize(input)
    # Set the input document attribute
    @input_document = REXML::Document.new(input)
    
    # Retrieve all of the handler info values and store them in a hash variable named @info_values.
    @info_values = {}
    REXML::XPath.each(@input_document, "/handler/infos/info") do |item|
      @info_values[item.attributes["name"]] = item.text.to_s.strip
    end

    # Retrieve all of the handler parameters and store them in a hash variable named @parameters.
    @parameters = {}
    REXML::XPath.each(@input_document, "/handler/parameters/parameter") do |item|
      @parameters[item.attributes["name"]] = item.text.to_s.strip
    end
  end

  # The execute method gets called by the task engine when the handler's node is processed. It is
  # responsible for performing whatever action the name indicates.
  # If it returns a result, it will be in a special XML format that the task engine expects. These
  # results will then be available to subsequent tasks in the process.
  def execute
    ##### SALESFORCE STUFF #####

    # Instanciate the Salesforce Client
    client = Restforce.new :username => @info_values["sf_username"],
    :password       => @info_values["sf_password"],
    :security_token => @info_values["sf_token"],
    :client_id      => @info_values["sf_client_id"],
    :client_secret  => @info_values["sf_client_secret"]

    # Call the Kinetic Request CE API
    begin
      space_slug = @parameters["space_slug"].empty? ? @info_values["space_slug"] : @parameters["space_slug"]

      # Submission API Route including Values
      submission_api_route = @info_values["api_server"] +
                             "/" + space_slug +
                             "/app/api/v1/submissions/" +
                             URI.escape(@parameters["submission_id"]) +
                             "/?include=values"

      # Retrieve the Submission Values
      submission_result = RestClient::Resource.new(
        submission_api_route,
        user: @info_values["api_username"],
        password: @info_values["api_password"]
      ).get

      # If the submission exists
      unless submission_result.nil?
        submission = JSON.parse(submission_result)["submission"]
        field_value = submission["values"][@parameters["field_name"]]
        # If the attachment field value exists
        unless field_value.nil?
          files = []
          # Attachment field values are stored as arrays, one map for each file attachment
          field_value.each_index do |index|
            file_info = field_value[index]
            # The attachment file name is stored in the 'name' property
            # API route to get the generated attachment download link from Kinetic Request CE.
            # "/{spaceSlug}/app/api/v1/submissions/{submissionId}/files/{fieldName}/{fileIndex}/{fileName}/url"
#            attachment_download_api_route = get_info_value(@input_document, 'api_server') +
#              file_info['link'] + "/url"
            attachment_download_api_route = @info_values["api_server"] +
              '/' + space_slug + '/app/api/v1' +
              '/submissions/' + URI.escape(@parameters['submission_id']) +
              '/files/' + URI.escape(@parameters['field_name']) +
              '/' + index.to_s +
              '/' + URI.escape(file_info['name']) +
              '/url'

            # Retrieve the URL to download the attachment from Kinetic Request CE.
            # This URL will only be valid for a short amount of time before it expires
            # (usually about 5 seconds).
            attachment_download_result = RestClient::Resource.new(
              attachment_download_api_route,
              user: @info_values["api_username"],
              password: @info_values["api_password"]
            ).get

            unless attachment_download_result.nil?
              url = JSON.parse(attachment_download_result)['url']
              file_info["url"] = url

              # Download File from Filehub
              response = RestClient.get(file_info["url"])

              # Upload File to Salesforce
              attachId = client.create 'Attachment', ParentId: @parameters["sf_parent_id"],
                Description: @parameters["sf_attachment_desc"],
                Name: file_info["name"],
                ContentType: file_info["contentType"],
                Body: Base64::encode64(response.body)
            end
            file_info.delete("link")
            file_info["sf_attachment_id"] = attachId
            files << file_info
          end
        end
      end

    # If the credentials are invalid
    rescue RestClient::Unauthorized
      raise StandardError, "(Unauthorized): You are not authorized."
    rescue RestClient::ResourceNotFound => error
      raise StandardError, error.response
    end

    # Build the results to be returned by this handler
    results = '';
    if files.nil?
      result = <<-RESULTS
      <results>
        <result name="files"></result>
      </results>
      RESULTS
    else
      results = <<-RESULTS
      <results>
        <result name="files">#{escape(JSON.dump(files))}</result>
      </results>
      RESULTS
    end

	# Return the results String
    return results
  end


  ##############################################################################
  # General handler utility functions
  ##############################################################################

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
