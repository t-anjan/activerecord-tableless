# See #ActiveRecord::Tableless

module ActiveRecord
  
  # = ActiveRecord::Tableless
  # 
  # Allow classes to behave like ActiveRecord models, but without an associated
  # database table. A great way to capitalize on validations. Based on the
  # original post at http://www.railsweenie.com/forums/2/topics/724 (which seems
  # to have disappeared from the face of the earth).
  # 
  # = Example usage
  # 
  #  class ContactMessage < ActiveRecord::Base
  #    
  #    has_no_table
  #    
  #    column :name,    :string
  #    column :email,   :string
  #    column :message, :string
  #    
  #  end
  #  
  #  msg = ContactMessage.new( params[:msg] )
  #  if msg.valid?
  #    ContactMessageSender.deliver_message( msg )
  #    redirect_to :action => :sent
  #  end
  #
  module Tableless
    
    class Exception < StandardError
    end
    class NoDatabase < Exception
    end

    def self.included( base ) #:nodoc:
      base.send :extend, ActsMethods
    end
    
    module ActsMethods #:nodoc:
      
      # A model that needs to be tableless will call this method to indicate
      # it.
      def has_no_table(options = {:database => :fail_fast})
        # keep our options handy
        if ActiveRecord::VERSION::STRING < "3.1.0"
          write_inheritable_attribute(:tableless_options,
                                      { :database => options[:database],
                                        :columns => []
                                      }
                                      )
          class_inheritable_reader :tableless_options
        else
          class_attribute :tableless_options
          self.tableless_options = {
            :database => options[:database],
            :columns => []
          }
        end

        # extend
        extend  ActiveRecord::Tableless::SingletonMethods
        extend  ActiveRecord::Tableless::ClassMethods
        
        # include
        include ActiveRecord::Tableless::InstanceMethods
        
        # setup columns
      end
      
      def tableless?
        false
      end
    end
    
    module SingletonMethods
      
      # Return the list of columns registered for the model. Used internally by
      # ActiveRecord
      def columns
        tableless_options[:columns]
      end
  
      # Register a new column.
      def column(name, sql_type = nil, default = nil, null = true)
        tableless_options[:columns] << ActiveRecord::ConnectionAdapters::Column.new(name.to_s, default, sql_type.to_s, null)
      end
      
      # Register a set of colums with the same SQL type
      def add_columns(sql_type, *args)
        args.each do |col|
          column col, sql_type
        end
      end

      %w(find create destroy).each do |m| 
        eval %{ 
          def #{m}(*args)
            logger.warn "Can't #{m} a Tableless object"
            false
          end
        }
      end
      
      def transaction(&block)
        case tableless_options[:database]
        when :pretend_succes
          yield
        when :fail_fast
          raise NoDatabase.new("Can't use transactions on Tableless object")
        else
          raise ArgumentError.new("Invalid option")
        end
      end
      
      def tableless?
        true
      end
    end
    
    module ClassMethods
          
      def from_query_string(query_string)
        unless query_string.blank?
          params = query_string.split('&').collect do |chunk|
            next if chunk.empty?
            key, value = chunk.split('=', 2)
            next if key.empty?
            value = value.nil? ? nil : CGI.unescape(value)
            [ CGI.unescape(key), value ]
          end.compact.to_h
          
          new(params)
        else
          new
        end
      end
      
    end
    
    module InstanceMethods
    
      def to_query_string(prefix = nil)
        attributes.to_a.collect{|(name,value)| escaped_var_name(name, prefix) + "=" + escape_for_url(value) if value }.compact.join("&")
      end
    
      def save(*args)
        case self.class.tableless_options[:database]
        when :pretend_succes
          true
        when :fail_fast
          raise NoDatabase.new("Can't save a Tableless object")
        else
          raise ArgumentError.new("Invalid option")
        end
      end

      def save!(*args)
        case self.class.tableless_options[:database]
        when :pretend_succes
          true
        when :fail_fast
          raise NoDatabase.new("Can't save! a Tableless object")
        else
          raise ArgumentError.new("Invalid option")
        end
      end

      def destroy
        case self.class.tableless_options[:database]
        when :pretend_succes
          @destroyed = true
          freeze
        when :fail_fast
          raise NoDatabase.new("Can't destroy a Tableless object")
        else
          raise ArgumentError.new("Invalid option")
        end
      end

      def reload(*args)
        case self.class.tableless_options[:database]
        when :pretend_succes
          self
        when :fail_fast
          raise NoDatabase.new("Can't reload a Tableless object")
        else
          raise ArgumentError.new("Invalid option")
        end
      end
      
      # def update_attributes(*args)
      #   case self.class.tableless_options[:database]
      #   when :pretend_succes
      #     self
      #   when :fail_fast
      #     raise NoDatabase.new("Can't reload a Tableless object")
      #   else
      #     raise ArgumentError.new("Invalid option")
      #   end
      # end
      
      private
      
        def escaped_var_name(name, prefix = nil)
          prefix ? "#{URI.escape(prefix)}[#{URI.escape(name)}]" : URI.escape(name)
        end
      
        def escape_for_url(value)
          case value
            when true then "1"
            when false then "0"
            when nil then ""
            else URI.escape(value.to_s)
          end
        rescue
          ""
        end
      
    end
    
  end
end

ActiveRecord::Base.send( :include, ActiveRecord::Tableless )
