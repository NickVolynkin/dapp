module Dapp
  module Dimg
    module Dapp
      module Command
        module Common
          def dimgstage_push_tag_format
            'dimgstage-%{signature}'
          end

          protected

          def dapp_project_dimgstages
            dapp_project_images.select { |image| image[:dimgstage] }
          end

          def dapp_project_dimgs
            dapp_project_images.select { |image| image[:dimg] }
          end

          def dapp_project_image_by_id(image_id)
            dapp_project_images.find { |image| image[:id] == image_id }
          end

          def dapp_project_image_labels(image)
            dapp_project_image_inspect(image)['Config']['Labels']
          end

          def dapp_project_image_inspect(image)
            image[:inspect] ||= begin
              cmd = shellout!("#{::Dapp::Dapp.host_docker} inspect --type=image #{image[:id]}")
              Array(JSON.parse(cmd.stdout.strip)).first || {}
            end
          end

          def dapp_project_images
            @dapp_project_images ||= [].tap do |images|
              images.concat prepare_docker_images(stage_cache, dimgstage: true)
              images.concat prepare_docker_images('-f label=dapp-dimg=true', dimg: true)
            end
          end

          def prepare_docker_images(extra_args, **extra_fields)
            [].tap do |images|
              shellout!(%(#{host_docker} images --format='{{if ne "<none>" .Tag }}{{.ID}};{{.Repository}}:{{.Tag}};{{.CreatedAt}}{{ end }}' -f "dangling=false" -f "label=dapp=#{name}" --no-trunc #{extra_args}))
                .stdout
                .lines
                .map(&:strip)
                .reject(&:empty?)
                .each do |l|
                id, name, created_at = l.split(';')
                images << { id: id, name: name, created_at: Time.parse(created_at).to_i, **extra_fields }
              end
            end
          end

          def remove_project_images(project_images, force: false)
            update_project_images_cache(project_images)
            remove_images(project_images_to_delete(project_images), force: force)
          end

          def update_project_images_cache(project_images)
            array_hash_delete_if_by_id(dapp_project_images, project_images)
          end

          def array_hash_delete_if_by_id(project_images, *images)
            project_images.delete_if { |image| images.flatten.any? { |i| image[:id] == i[:id] } }
          end

          def project_images_to_delete(project_images)
            project_images.map { |image| image[:dangling] ? image[:id] : image[:name] }
          end

          def dapp_containers_flush_by_label(label)
            log_proper_containers do
              remove_containers_by_query(%(#{host_docker} ps -a -f "label=#{label}" -f "name=dapp.build." -q --no-trunc))
            end
          end

          def dapp_dangling_images_flush_by_label(label)
            log_proper_flush_dangling_images do
              remove_images_by_query(%(#{host_docker} images -f "dangling=true" -f "label=#{label}" -q --no-trunc))
            end
          end

          def dapp_tagless_images_flush
            remove_images_by_query(%(#{host_docker} images --format='{{if eq "<none>" .Tag }}{{.ID}}{{ end }}' -f "dangling=false" -f "label=dapp" -q --no-trunc))
          end

          def remove_images_by_query(images_query)
            with_subquery(images_query) { |ids| remove_images(ids) }
          end

          def remove_images(images_ids_or_names, force: false)
            ids_chunks(images_ids_or_names) do |chunk|
              chunk = ignore_used_images(chunk) unless force
              remove_base("#{host_docker} rmi%{force_option} %{ids}", chunk, force: force)
            end
          end

          def ignore_used_images(images_ids_or_names)
            not_used_images = proc do |*image_id_or_name, log: true|
              images = image_id_or_name.flatten
              filters = images.map { |iion| "--filter=ancestor=#{iion}" }.join(' ')
              res = shellout!(%(#{host_docker} ps -a -q #{filters})).stdout.strip
              if res.empty?
                true
              else
                log_info("Skip `#{images.join('`, `')}` (used by containers: #{res.split.join(' ')})") if log
                false
              end
            end

            if not_used_images.call(images_ids_or_names, log: false)
              images_ids_or_names
            else
              images_ids_or_names.select(&not_used_images)
            end
          end

          def remove_containers_by_query(containers_query)
            with_subquery(containers_query) { |ids| remove_containers(ids) }
          end

          def remove_containers(ids)
            ids_chunks(ids) do |chunk|
              remove_base("#{host_docker} rm%{force_option} %{ids}", chunk, force: true)
            end
          end

          def ids_chunks(ids, &blk)
            return if ids.empty?
            ids.uniq.each_slice(50, &blk)
          end

          def remove_base(query_format, ids, force: false)
            return if ids.empty?
            force_option = force ? ' -f' : ''
            log(ids.join("\n")) if log_verbose? || dry_run?
            run_command(format(query_format, force_option: force_option, ids: ids.join(' ')))
          end

          def with_subquery(query)
            return if (res = shellout!(query).stdout.strip.lines.map(&:strip)).empty?
            yield(res)
          end

          def run_command(cmd)
            shellout!(cmd) unless dry_run?
          end

          def dimg_import_export_base(should_be_built: true)
            repo = option_repo
            validate_repo_name!(repo)
            build_configs.each do |config|
              log_dimg_name_with_indent(config) do
                yield dimg(config: config, should_be_built: should_be_built)
              end
            end
          end

          def validate_repo_name!(repo)
            raise ::Dapp::Error::Command, code: :repo_name_incorrect, data: { name: repo } unless ::Dapp::Dimg::DockerRegistry.repo_name?(repo)
          end

          def validate_image_name!(image)
            raise ::Dapp::Error::Command, code: :image_name_incorrect, data: { name: image } unless ::Dapp::Dimg::Image::Docker.image_name?(image)
          end

          def validate_tag_name!(tag)
            raise ::Dapp::Error::Command, code: :tag_name_incorrect, data: { name: tag } unless ::Dapp::Dimg::Image::Docker.tag?(tag)
          end

          def proper_cache_version?
            !!options[:proper_cache_version]
          end

          def log_proper_cache(&blk)
            log_step_with_indent(:'proper cache', &blk)
          end

          def log_proper_repo_cache(&blk)
            log_step_with_indent(:'proper repo cache', &blk)
          end

          def log_proper_containers(&blk)
            log_step_with_indent(:'proper containers', &blk)
          end

          def log_proper_flush_dangling_images(&blk)
            log_step_with_indent(:'proper dangling', &blk)
          end

          def push_format(dimg_name)
            if dimg_name.nil?
              spush_format
            else
              '%{repo}/%{dimg_name}:%{tag}'
            end
          end

          def spush_format
            '%{repo}:%{tag}'
          end

          def dimgstage_push_format
            "%{repo}:#{dimgstage_push_tag_format}"
          end

          def with_stages?
            !!options[:with_stages]
          end
        end
      end
    end
  end # Dimg
end # Dapp
