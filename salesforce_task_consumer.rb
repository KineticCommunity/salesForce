module KineticTask
  module Consumers
    class SalesforceTaskConsumer
      VERSION = "1.0.0"
      # Specify the source name
      SOURCE_NAME ||= "Salesforce Task"  

      # Register the JiraConsumer with the Base consumer so that it is accessible by the Engine.
      KineticTask::Consumer::Base.register "Salesforce Task", self

      # Stores the initial hash used to configure the adapter
      attr_accessor :spec

      def initialize(spec={})
        # Store the spec
        @spec = spec
      end

      #########################################################################
      # CLASS METHODS
      #########################################################################

      # Returns an Array of Hash objects that define what properties are
      # configurable for this consumer (IE: Server, Username, Password, Port, Web Server).
      def self.configurable_properties
        [] # can put properties like handler info values 
      end

      # Indicates whether this consumer allows multiple source instances
      def self.allows_multiple_sources
        true # should stay true most likely
      end
      
      # source_data_label and source_data_description describe source data (aka when clicking run tree form)
      def self.source_data_label
        "Salesforce XML Parameters"
      end
      
      def self.source_data_description
        "The source data for Salesforce is an XML string that contains info about a created or modified task."
      end

      #########################################################################
      # INSTANCE METHODS
      #########################################################################

      # Given the source group of a Kinetic Request catalog and template name,
      # build the map of bindable variables that defines the Task Builder node
      # parameter menu.
      def retrieve_binding_definition(source_group)
        # Return the application bindings map
        {
          'Salesforce Task' => {
            'Organization Id'  => '<%=@salesforce_task["OrganizationId"]%>',
            'Task Id' => '<%=@salesforce_task["Id"]%>',
            'Account Id' => '<%=@salesforce_task["AccountId"]%>',
            'Created By Id' => '<%=@salesforce_task["CreatedById"]%>',
            'Created Date' => '<%=@salesforce_task["CreatedDate"]%>',
            'Is Archived' => '<%=@salesforce_task["IsArchived"]%>',
            'Is Closed' => '<%=@salesforce_task["IsClosed"]%>',
            'Is Deleted' => '<%=@salesforce_task["IsDeleted"]%>',
            'Last Modified By Id' => '<%=@salesforce_task["LastModifiedById"]%>',
            'Last Modified Date' => '<%=@salesforce_task["LastModifiedDate"]%>',
            'Owner Id' => '<%=@salesforce_task["OwnerId"]%>',
            'Priority' => '<%=@salesforce_task["Priority"]%>',
            'Reminder Date Time' => '<%=@salesforce_task["ReminderDateTime"]%>',
            'Status' => '<%=@salesforce_task["Status"]%>',
            'Subject' => '<%=@salesforce_task["Subject"]%>',
            'Type' => '<%=@salesforce_task["Type"]%>',
            'Who Id' => '<%=@salesforce_task["WhoId"]%>'
          }
        }
      end

      # Given a source group and source id, this consumer builds up the data
      # necessary to process a task tree triggered by that source record.
      def build_bindings(source_group, source_id, source_data=nil)
        # Initialize the bindings hash
        bindings = {}
        
        # Initialize the salesforce_task variable and initialize fields that could
        # be absent because they have no values as empty string to avoid errors
        bindings["salesforce_task"] = {"AccountId" => "", "Priority" => "", "ReminderDateTime" => "",
            "Type" => "", "WhoId" => "", "Description" => ""}

        # Read the file contents and create a new XML document.
        doc = REXML::Document.new(source_data)

        # Raise an error if there was a problem parsing the file contents.
        if (doc.root.nil?)
          raise "Could not parse source data as an XML document"
        end

        normal_fields = [ "Id","CreatedById","IsArchived","IsClosed","IsDeleted","Description",
            "LastModifiedById","OwnerId","Priority","Status","Subject", "Type","WhoId"]

        date_fields = [ "CreateDate","LastModifiedDate","ReminderDateTime" ]

        REXML::XPath.each(doc, 'soapenv:Envelope/soapenv:Body/notifications') do |element|
          bindings["salesforce_task"]["OrganizationId"] = element.elements["OrganizationId"].text 
          element.elements["Notification"].elements["sObject"].each do |properties|
            if (properties.methods.include?(:name) && normal_fields.include?(properties.name))
              bindings["salesforce_task"][properties.name] = properties.text
            elsif (properties.methods.include?(:name) && date_fields.include?(properties.name))
              bindings["salesforce_task"][properties.name] = Time.parse(properties.text)
            end
          end
        end

        # Return the bindings hash
        bindings
      end

      def retrieve_source_details(source_group, submission_id)
      end

      def retrieve_source_id(source_group, submission_id)
      end

      # Returns a hash that defines the following values:  source_data and source_id.  This
      # particular handler simply sets the source data to the body content that was passed to the
      # api call and gets the source id from the posted xml data.
      def run_tree_handler(bodyContent, httpRequest)
        # Attempt to extract the source id from the source data xml.
        source_id = nil
        doc = REXML::Document.new(bodyContent)
        REXML::XPath.each(doc, 'soapenv:Envelope/soapenv:Body/notifications') do |element|
          source_id = element.elements["Notification"].elements["sObject"].elements["sf:Id"].text
        end

        # If the source id could not be determined from the source data xml raise an error.
        if source_id.nil?
          raise "Could not extract source id from the source data xml"
        end

        # Return the source_data and source_id.
        {
          "source_data" => bodyContent,
          "source_id"   => source_id
        }
      end
      
      # Returns a hash that defines the following values:  token and message.  For this consumer we
      # raise an error because it does not support updating deferred tasks.
      def update_deferred_task_handler(bodyContent, httpRequest)
        raise "The update deferred task method is not supported by the Salesforce Task consumer"
      end

      # Returns a hash that defines the following values:  token, message, and results.  For this
      # consumer we raise an error because it does not support completing deferred tasks.
      def complete_deferred_task_handler(bodyContent, httpRequest)
        raise "The complete deferred task method is not supported by the Salesforce Task consumer"
      end

      # Validate the configuration, returning an non-empty string if there were problems
      # usually used to validate configurable properties
      def validate
      end
    end
  end
end