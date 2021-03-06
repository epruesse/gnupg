#!/usr/bin/env gpgscm

;; Copyright (C) 2016 g10 Code GmbH
;;
;; This file is part of GnuPG.
;;
;; GnuPG is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 3 of the License, or
;; (at your option) any later version.
;;
;; GnuPG is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with this program; if not, see <http://www.gnu.org/licenses/>.

(load (with-path "defs.scm"))
(setup-environment)

 ;; XXX because of --always-trust, the trustdb is not created.
 ;; Therefore, we redefine GPG without --always-trust.
(define GPG `(,(tool 'gpg) --no-permission-warning))

(define (exact id)
  (string-append "=" id))

(define (count-uids-of-secret-key id)
  (length (filter (lambda (x) (and (string=? "uid" (car x))
				   (not (string=? "r" (cadr x)))))
		  (gpg-with-colons
		   `(--with-fingerprint
		     --list-secret-keys ,(exact id))))))

(define alpha "Alpha <alpha@invalid.example.net>")
(define bravo "Bravo <bravo@invalid.example.net>")

(define (key-data key)
  (filter (lambda (x) (or (string=? (car x) "pub")
                          (string=? (car x) "sub")))
          (gpg-with-colons `(-k ,key))))

(setenv "PINENTRY_USER_DATA" "test" #t)

(info "Checking quick key generation...")
(call-check `(,@GPG --quick-generate-key ,alpha))

(define keyinfo (gpg-with-colons `(-k ,(exact alpha))))
(define fpr (:fpr (assoc "fpr" keyinfo)))

(assert (= 1 (count-uids-of-secret-key alpha)))
(assert (not (equal? "" (:expire (assoc "pub" keyinfo)))))

(info "Checking that we can add a user ID...")

;; Make sure the key capabilities don't change when we add a user id.
;; (See bug #2697.)
(let ((pre (key-data (exact alpha)))
      (result (call-check `(,@GPG --quick-add-uid ,(exact alpha) ,bravo)))
      (post (key-data (exact alpha))))
  (if (not (equal? pre post))
      (begin
	(display "Key capabilities changed when adding a user id:")
	(newline)
	(display "  Pre: ")
	(display pre)
	(newline)
	(display " Post: ")
	(display post)
	(newline)
	(exit 1))))

(assert (= 2 (count-uids-of-secret-key alpha)))
(assert (= 2 (count-uids-of-secret-key bravo)))

(info "Checking that we can revoke a user ID...")
(call-check `(,@GPG --quick-revoke-uid ,(exact bravo) ,alpha))

(assert (= 1 (count-uids-of-secret-key bravo)))

(info "Checking that we can change the expiration time.")

(define (expiration-time id)
  (:expire (assoc "pub" (gpg-with-colons `(-k ,id)))))

;; Remove the expiration date.
(call-check `(,@gpg --quick-set-expire ,fpr "0"))
(assert (equal? "" (expiration-time fpr)))

;; Make the key expire in one year.
(call-check `(,@gpg --quick-set-expire ,fpr "1y"))
;; XXX It'd be nice to check that the value is right.
(assert (not (equal? "" (expiration-time fpr))))


;;
;; Check --quick-addkey
;;

;; Get the subkeys.
(define (get-subkeys)
  (filter (lambda (x) (equal? "sub" (car x)))
	  (gpg-with-colons `(-k ,fpr))))

;; This keeps track of the number of subkeys.
(define count (length (get-subkeys)))

(for-each-p
 "Checking that we can add subkeys..."
 (lambda (args check)
   (set! count (+ 1 count))
   (call-check `(,@gpg --quick-add-key ,fpr ,@args))
   (let ((subkeys (get-subkeys)))
     (assert (= count (length subkeys)))
     (if check (check (last subkeys)))))
 ;; A bunch of arguments...
 '(()
   (- - -)
   (default default never)
   (rsa sign "2d")
   (rsa1024 sign "2w")
   (rsa2048 encr "2m")
   (rsa4096 sign,auth "2y")
   (future-default))
 ;; ... with functions to check that the created key matches the
 ;; expectations (or #f for no tests).
 (list
  #f
  #f
  (lambda (subkey)
    (assert (equal? "" (:expire subkey))))
  (lambda (subkey)
    (assert (= 1 (:alg subkey)))
    (assert (string-contains? (:cap subkey) "s"))
    (assert (not (equal? "" (:expire subkey)))))
  (lambda (subkey)
    (assert (= 1 (:alg subkey)))
    (assert (= 1024 (:length subkey)))
    (assert (string-contains? (:cap subkey) "s"))
    (assert (not (equal? "" (:expire subkey)))))
  (lambda (subkey)
    (assert (= 1 (:alg subkey)))
    (assert (= 2048 (:length subkey)))
    (assert (string-contains? (:cap subkey) "e"))
    (assert (not (equal? "" (:expire subkey)))))
  (lambda (subkey)
    (assert (= 1 (:alg subkey)))
    (assert (= 4096 (:length subkey)))
    (assert (string-contains? (:cap subkey) "s"))
    (assert (string-contains? (:cap subkey) "a"))
    (assert (not (equal? "" (:expire subkey)))))
  #f))
