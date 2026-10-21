(define-module (kanata-service)
  #:use-module (gnu services)
  #:use-module (gnu services desktop)
  #:use-module (guix gexp)
  #:export (kanata-gasc-service))

(define kanata-gasc-service
  (service kanata-service-type
           (kanata-configuration
            (keymaps (list (local-file "../kanata.kbd"))))))
