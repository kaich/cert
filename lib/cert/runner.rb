require 'fileutils'

module Cert
  class Runner
    def launch
      run

      installed = FastlaneCore::CertChecker.installed?(ENV["CER_FILE_PATH"])
      UI.message "Verifying the certificated is properly installed locally..."
      UI.user_error!("Could not find the newly generated certificate installed") unless installed
      UI.success "Successfully installed certificate #{ENV['CER_CERTIFICATE_ID']}"
      return ENV["CER_FILE_PATH"]
    end

    def login
      UI.message "Starting login with user '#{Cert.config[:username]}'"
      Spaceship.login(Cert.config[:username], nil)
      Spaceship.select_team
      UI.message "Successfully logged in"
    end

    def run
      FileUtils.mkdir_p(Cert.config[:output_path])

      FastlaneCore::PrintTable.print_values(config: Cert.config, hide_keys: [:output_path], title: "Summary for cert #{Cert::VERSION}")

      login

      should_create = Cert.config[:force]
      unless should_create
        cert_path = find_existing_cert
        should_create = cert_path.nil?
      end

      return unless should_create
      
    end


    def expired_certs
      certificates.select do |certificate|
        certificate.expires < Time.now.utc
      end
    end

    def find_existing_cert
      certificates.each do |certificate|
        unless certificate.can_download
          next
        end

        path = store_certificate(certificate)

        if FastlaneCore::CertChecker.installed?(path)
          # This certificate is installed on the local machine
          ENV["CER_CERTIFICATE_ID"] = certificate.id
          ENV["CER_FILE_PATH"] = path

          UI.success "Found the certificate #{certificate.id} (#{certificate.name}) which is installed on the local machine. Using this one."

          return path
        elsif File.exist?(path)
          KeychainImporter.import_file(path)

          ENV["CER_CERTIFICATE_ID"] = certificate.id
          ENV["CER_FILE_PATH"] = path

          UI.success "Found the cached certificate #{certificate.id} (#{certificate.name}). Using this one."

          return path
        else
          UI.error "Certificate #{certificate.id} (#{certificate.name}) can't be found on your local computer"
        end

        File.delete(path) # as apparantly this certificate is pretty useless without a private key
      end

      UI.important "Couldn't find an existing certificate... creating a new one"
      return nil
    end

    # All certificates of this type
    def certificates
      certificate_type.all
    end

    # The kind of certificate we're interested in
    def certificate_type
      cert_type = Spaceship.certificate.production
      cert_type = Spaceship.certificate.in_house if Spaceship.client.in_house?
      cert_type = Spaceship.certificate.development if Cert.config[:development]

      cert_type
    end


    def store_certificate(certificate)
      path = File.expand_path(File.join(Cert.config[:output_path], "#{certificate.id}.cer"))
      puts "----------------------------:#{path}"
      raw_data = certificate.download_raw
      File.write(path, raw_data)
      return path
    end
  end
end
