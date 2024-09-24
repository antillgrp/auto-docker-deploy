  while : ; do
    case "${1-}" in
      -c | --config-file)
          [[ "${args[*]}" == *"-w"* ]] || [[ "${args[*]}" == *"--wipe-out"* ]] &&
          fail " ${RED}[ERROR]${NOFORMAT} With (-w, --wipe-out) option no more option are compatible"

          [[ -z "${2-}" ]] &&
          fail " ${RED}[ERROR]${NOFORMAT} With (-c, --config-file) option, file path is expected"

          CONFIG_FILE="${2-}"
          shift
          ;;
      -g | --generate-compose)
          [[ -n "${2-}" ]] && [[ ! "${2-}" == -* ]] && fail " ${RED}[ERROR]${NOFORMAT} Unexpected parameter: ${2-}"

          [[ "${args[*]}" == *"-w"* ]] || [[ "${args[*]}" == *"--wipe-out"* ]] &&
          fail " ${RED}[ERROR]${NOFORMAT} With (-w, --wipe-out) option no more option are compatible"
          ;;
      -u | --undo-deploy)
          [[ -n "${2-}" ]] && [[ ! "${2-}" == -* ]] && fail " ${RED}[ERROR]${NOFORMAT} Unexpected parameter: ${2-}"

          [[ "${args[*]}" == *"-w"* ]] || [[ "${args[*]}" == *"--wipe-out"* ]] &&
          fail " ${RED}[ERROR]${NOFORMAT} With (-w, --wipe-out) option no more option are compatible"
          ;;
      -d | --deploy)
          [[ -n "${2-}" ]] && [[ ! "${2-}" == -* ]] && fail " ${RED}[ERROR]${NOFORMAT} Unexpected parameter: ${2-}"

          [[ "${args[*]}" == *"-w"* ]] || [[ "${args[*]}" == *"--wipe-out"* ]] &&
          fail " ${RED}[ERROR]${NOFORMAT} With (-w, --wipe-out) option no more option are compatible"
          ;;
      -t | --tag)
          [[ "${args[*]}" == *"-w"* ]] || [[ "${args[*]}" == *"--wipe-out"* ]] &&
          fail " ${RED}[ERROR]${NOFORMAT} With (-w, --wipe-out) option no more option are compatible"

          [[ -z "${2-}" ]] &&
          fail " ${RED}[ERROR]${NOFORMAT} With (-t, --tag) option, tag (string) is expected"

          INSTALL_TAG="${2-}"
          shift
          ;;
      -h | --help) 
          [[ -n "${2-}" ]] && fail " ${RED}[ERROR]${NOFORMAT} Unexpected parameter: ${2-}"
        
          help && exit 
          ;; 
      -v | --version) 
          [[ -n "${2-}" ]] && fail " ${RED}[ERROR]${NOFORMAT} Unexpected parameter: ${2-}"
        
          version && exit 
          ;; 
      -e | --encrypt)
          [[ -n "${2-}" ]] && fail " ${RED}[ERROR]${NOFORMAT} Unexpected parameter: ${2-}"

          openssl aes-128-cbc -k "solutions@123" -e -pbkdf2 -iter 100 -a -salt < "$(basename "${BASH_SOURCE[0]}")" > \
          "$(basename "${BASH_SOURCE[0]}")".aes
        
          # decrypt --> cat deploy-certscan-docker-X.Y.Z.sh.aes | \
          # openssl aes-128-cbc -d -pbkdf2 -iter 100 -a -salt -k "solutions@123" > \
          # deploy-certscan-docker-X.Y.Z.sh
          ;;
      -w | --wipe-out)
          [[ -n "${2-}" ]] && fail " ${RED}[ERROR]${NOFORMAT} Unexpected parameter: ${2-}"

          fail "Option (-w | --wipe-out) no yet implemented"
          ;;
      -?*) fail " ${RED}[ERROR]${NOFORMAT} Unknown option: ${2-}";;
        *) break ;;
    esac
    shift
  done