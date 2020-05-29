require 'surveyor/common'
require 'rabl'

module Surveyor
  module Models
    module SurveyMethodsMultitenant
      extend ActiveSupport::Concern
      include ActiveModel::Validations
      include ActiveModel::ForbiddenAttributesProtection

      included do
        # Associations
        has_many :sections, class_name: 'SurveySection', :dependent => :destroy
        has_many :response_sets
        has_many :translations, :class_name => "SurveyTranslation"
        attr_accessible *PermittedParams.new.survey_attributes if defined? ActiveModel::MassAssignmentSecurity

        # Validations
        validates_presence_of :title
        # this validation (including study_id scope) will be added back in the
        # multitenant project (using acts_as_tenant) implementation of this module.
        #validates_uniqueness_of :survey_version, :scope => :access_code, :message => "survey with matching access code and version already exists"

        # Generated attributes.  Use before_validation instead of before_save so that generated attributes have values before the validates_uniqueness is applied.
        before_validation :generate_access_code
        before_validation :increment_version
        before_validation :set_display_order
      end

      module ClassMethods
        def to_normalized_string(value)
          # replace non-alphanumeric with "-". remove repeat "-"s. don't start or end with "-"
          value.to_s.downcase.gsub(/[^a-z0-9]/,"-").gsub(/-+/,"-").gsub(/-$|^-/,"")
        end
      end

      # Instance methods
      def initialize(*args)
        super(*args)
        default_args
      end

      def finish_button_text; end

      def default_args
        self.api_id ||= Surveyor::Common.generate_api_id
      end

      def active?
        self.active_as_of?(DateTime.now)
      end
      def active_as_of?(date)
        (active_at && active_at < date && (!inactive_at || inactive_at > date)) ? true : false
      end
      def activate!
        self.active_at = DateTime.now
        self.inactive_at = nil
      end
      def deactivate!
        self.inactive_at = DateTime.now
        self.active_at = nil
      end

      def as_json(options = nil)
        template_paths = ActionController::Base.view_paths.collect(&:to_path)
        Rabl.render(filtered_for_json, 'surveyor/export.json', :view_path => template_paths, :format => "hash")
      end

      ##
      # A hook that allows the survey object to be modified before it is
      # serialized by the #as_json method.
      def filtered_for_json
        self
      end

      def default_access_code
        self.class.to_normalized_string(title)
      end

      def generate_access_code
        self.access_code ||= default_access_code
      end

      def increment_version
        return if survey_version_changed? # Explicitly set

        current_version = self.class.where(:access_code => access_code)
                                    .maximum(:survey_version)

        self.survey_version = current_version.nil? ? 0 : (current_version + 1)
      end

      def translation(locale_symbol)
        t = self.translations.where(:locale => locale_symbol.to_s).first
        {:title => self.title, :description => self.description}.with_indifferent_access.merge(
          t ? YAML.load(t.translation || "{}").with_indifferent_access : {}
        )
      end

      private

      def set_display_order
        self.display_order ||= Survey.count
      end
    end
  end
end
