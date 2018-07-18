module Dapp
  module Dimg
    class Dimg
      include GitArtifact
      include Path
      include Stages

      include Helper::Sha256
      include Helper::Trivia

      attr_reader :config
      attr_reader :ignore_signature_auto_calculation
      attr_reader :should_be_built
      attr_reader :dapp

      def initialize(config:, dapp:, should_be_built: false, ignore_signature_auto_calculation: false)
        @config = config
        @dapp = dapp

        @ignore_signature_auto_calculation = ignore_signature_auto_calculation

        @dapp._terminate_dimg_on_terminate(self)

        enable_should_be_built if should_be_built
        should_be_built!
      end

      def enable_should_be_built
        @should_be_built = true
      end

      def should_be_built!
        raise Error::Dimg, code: :dimg_not_built if should_be_built?
      end

      def name
        config._name
      end

      def terminate
        cleanup_tmp
      end

      def build!
        dapp.lock("#{dapp.name}.images", readonly: true) do
          last_stage.build_lock! do
            begin
              builder.before_build_check
              last_stage.build!
            ensure
              after_stages_build!
            end
          end
        end
      end

      def after_stages_build!
        last_stage.save_in_cache!
        artifacts.each { |artifact| artifact.last_stage.save_in_cache! }
      end

      def tag!(repo, format:)
        dimg_export_base!(repo, export_format: format)
      end

      def export!(repo, format:)
        dimg_export_base!(repo, export_format: format, push: true)
      end

      def export_stages!(repo, format:)
        dapp.lock("#{dapp.name}.images", readonly: true) do
          export_images.each do |stage_image|
            signature = stage_image.name.split(':').last
            image_name = format(format, repo: repo, signature: signature)

            if dimgstage_should_not_be_pushed?(format(dapp.dimgstage_push_tag_format, signature: signature))
              dapp.log_state(image_name, state: dapp.t(code: 'state.exist'))
              next
            end

            export_base!(image_name, push: true) do
              stage_image.export!(image_name)
            end
          end
          artifacts.each { |artifact| artifact.export_stages!(repo, format: format) }
        end
      end

      def dimg_export_base!(repo, export_format:, push: false)
        dapp.lock("#{dapp.name}.images", readonly: true) do
          dapp.tags_by_scheme.each do |tag_scheme_name, tags|
            dapp.log_step_with_indent(tag_scheme_name) do
              tags.each do |tag|
                image_name = format(export_format, repo: repo, dimg_name: name, tag: tag)

                if push && tag_should_not_be_pushed?(tag.to_s)
                  dapp.log_state(image_name, state: dapp.t(code: 'state.exist'))
                  next
                end

                export_base!(image_name, push: push) do
                  export_image = build_export_image!(image_name, scheme_name: tag_scheme_name)
                  if push
                    export_image.export!
                  else
                    export_image.tag!
                  end
                end
              end
            end unless tags.empty?
          end
        end
      end

      def dimgstage_should_not_be_pushed?(signature)
        registry_dimgstages_tags.include?(signature)
      end

      def tag_should_not_be_pushed?(tag)
        registry_tags.include?(tag) && begin
          registry_tag_parent = registry.image_history(tag, name)['container_config']['Image']
          registry_tag_parent == last_stage.image.built_id
        end
      end

      def registry_tags
        @registry_tags ||= begin
          if name.nil?
            registry.nameless_dimg_tags
          else
            registry.dimg_tags(name)
          end
        end
      end

      def registry_dimgstages_tags
        @registry_dimgstages_tags ||= registry.dimgstages_tags
      end

      def registry
        @registry ||= dapp.dimg_registry
      end

      def build_export_image!(image_name, scheme_name:)
        Image::Dimg.image_by_name(name: image_name, from: last_stage.image, dapp: dapp).tap do |export_image|
          export_image.untag! if export_image.built?
          export_image.add_service_change_label(:'dapp-tag-scheme' => scheme_name)
          export_image.add_service_change_label(:'dapp-dimg' => true)
          export_image.build!
        end
      end

      def export_base!(image_name, push: true)
        if dapp.dry_run?
          dapp.log_state(image_name, state: dapp.t(code: push ? 'state.push' : 'state.export'), styles: { status: :success })
        else
          dapp.lock("image.#{hashsum image_name}") do
            ::Dapp::Dimg::Image::Docker.reset_image_inspect(image_name)
            dapp.log_process(image_name, process: dapp.t(code: push ? 'status.process.pushing' : 'status.process.exporting')) { yield }
          end
        end
      end

      def import_stages!(repo, format:)
        dapp.lock("#{dapp.name}.images", readonly: true) do
          import_images.each do |image|
            signature = image.name.split(':').last
            image_name = format(format, repo: repo, signature:signature )

            unless dimgstage_should_not_be_pushed?(format(dapp.dimgstage_push_tag_format, signature: signature))
              dapp.log_state(image_name, state: dapp.t(code: 'state.not_exist'))
              next
            end

            begin
              import_base!(image, image_name)
            rescue ::Dapp::Error::Shellout => e
              dapp.log_info ::Dapp::Helper::NetStatus.message(e)
              next
            end
            break unless !!dapp.options[:pull_all_stages]
          end
          artifacts.each { |artifact| artifact.import_stages!(repo, format: format) }
        end
      end

      def import_base!(image, image_name)
        if dapp.dry_run?
          dapp.log_state(image_name, state: dapp.t(code: 'state.pull'), styles: { status: :success })
        else
          dapp.lock("image.#{hashsum image_name}") do
            dapp.log_process(image_name,
                             process: dapp.t(code: 'status.process.pulling'),
                             status: { failed: dapp.t(code: 'status.failed.not_pulled') },
                             style: { failed: :secondary }) do
              image.import!(image_name)
            end
          end
        end
      end

      def run(docker_options, command)
        run_stage(nil, docker_options, command)
      end

      def run_stage(stage_name, docker_options, command)
        stage_image = (stage_name.nil? ? last_stage : stage_by_name(stage_name)).image
        raise Error::Dimg, code: :dimg_stage_not_built, data: { stage_name: stage_name } unless stage_image.built?
        cmd = "#{dapp.host_docker} run #{[docker_options, stage_image.built_id, command].flatten.compact.join(' ')}"
        if dapp.dry_run?
          dapp.log(cmd)
        else
          system(cmd) || raise(Error::Dimg, code: :dimg_not_run)
        end
      end

      def stage_image_name(stage_name)
        stages.find { |stage| stage.name == stage_name }.image.name
      end

      def builder
        @builder ||= Builder.const_get(config._builder.capitalize).new(self)
      end

      def artifacts
        @artifacts ||= artifacts_stages.map { |stage| stage.artifacts.map { |artifact| artifact[:dimg] } }.flatten
      end

      def artifact?
        false
      end

      def scratch?
        config._docker._from.nil? && config._from_dimg.nil? && config._from_dimg_artifact.nil?
      end

      def dev_mode?
        dapp.dev_mode?
      end

      def build_cache_version
        [::Dapp::BUILD_CACHE_VERSION, dev_mode? ? 1 : 0]
      end

      def cleanup_tmp
        return unless tmp_dir_exists?

        # В tmp-директории могли остаться файлы, владельцами которых мы не являемся.
        # Такие файлы могут попасть туда при экспорте файлов артефакта.
        # Чтобы от них избавиться — запускаем docker-контейнер под root-пользователем
        # и удаляем примонтированную tmp-директорию.
        cmd = "".tap do |cmd|
          cmd << "#{dapp.host_docker} run --rm"
          cmd << " --volume #{dapp.tmp_base_dir}:#{dapp.tmp_base_dir}"
          cmd << " --label dapp=#{dapp.name}"
          cmd << " alpine:3.6"
          cmd << " rm -rf #{tmp_path}"
        end
        dapp.shellout! cmd
      end

      def stage_should_be_introspected_before_build?(name)
        dapp.options[:introspect_before] == name
      end

      def stage_should_be_introspected_after_build?(name)
        dapp.options[:introspect_stage] == name
      end

      protected

      def should_be_built?
        should_be_built && begin
          builder.before_dimg_should_be_built_check
          !last_stage.image.tagged?
        end
      end
    end # Dimg
  end # Dimg
end # Dapp
