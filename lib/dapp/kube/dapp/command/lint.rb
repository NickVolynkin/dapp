module Dapp
  module Kube
    module Dapp
      module Command
        module Lint
          def kube_chart_name
            chart_spec = yaml_load_file(kube_chart_yaml_path)

            if chart_spec["name"].nil? || chart_spec["name"].empty?
              raise ::Dapp::Error::Command, code: :no_helm_chart_spec_name, data: { name: chart_spec["name"], path: kube_chart_yaml_path, raw_spec: kube_chart_yaml_path.read.strip }
            end

            chart_spec["name"]
          end

          def with_kube_tmp_lint_chart_dir(&blk)
            old_kube_tmp_helm_chart_dir = @kube_tmp_helm_chart_dir
            unless ENV['DAPP_HELM_CHART_DIR']
              @kube_tmp_helm_chart_dir = File.join(Dir.mktmpdir('dapp-helm-lint-', tmp_base_dir), kube_chart_name)
            end

            begin
              with_kube_tmp_chart_dir(&blk)
            ensure
              @kube_tmp_helm_chart_dir = old_kube_tmp_helm_chart_dir
            end
          end

          def kube_lint
            kube_check_helm_chart_yaml!
            with_kube_tmp_lint_chart_dir do
              helm_release(&:lint!)
            end
          end

          def kube_check_helm_chart_yaml!
            raise ::Dapp::Error::Command, code: :chart_yaml_not_found, data: { path: kube_chart_yaml_path } unless kube_chart_yaml_path.exist?
          end

          def kube_chart_yaml_path
            kube_chart_path.join("Chart.yaml")
          end
        end
      end
    end
  end
end
