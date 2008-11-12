;;; Waxeye Parser Generator
;;; www.waxeye.org
;;; Copyright (C) 2008 Orlando D. A. R. Hill
;;;
;;; Permission is hereby granted, free of charge, to any person obtaining a copy of
;;; this software and associated documentation files (the "Software"), to deal in
;;; the Software without restriction, including without limitation the rights to
;;; use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
;;; of the Software, and to permit persons to whom the Software is furnished to do
;;; so, subject to the following conditions:
;;;
;;; The above copyright notice and this permission notice shall be included in all
;;; copies or substantial portions of the Software.
;;;
;;; THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
;;; IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
;;; FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
;;; AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
;;; LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
;;; OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
;;; SOFTWARE.


(module
c
mzscheme

(require (lib "ast.ss" "waxeye")
         (lib "fa.ss" "waxeye")
         (only (lib "list.ss" "mzlib") filter)
         "code.scm" "dfa.scm" "gen.scm" "util.scm")
(provide gen-c)


(define *c-prefix* "")
(define *c-parser-name* "")
(define *c-type-name* "")
(define *c-header-name* "")
(define *c-source-name* "")


(define (gen-c-names)
  (set! *c-prefix* (if *name-prefix*
                       (string-append (camel-case-lower *name-prefix*) "_")
                       ""))
  (set! *c-parser-name* (string-append *c-prefix* "parser"))
  (set! *c-type-name* (string-append *c-prefix* "type"))
  (set! *c-header-name* (string-append *c-parser-name* ".h"))
  (set! *c-source-name* (string-append *c-parser-name* ".c")))


(define (gen-c grammar path)
  (indent-unit! 4)
  (gen-c-names)
  (dump-string (gen-header grammar) (string-append path *c-header-name*))
  (dump-string (gen-parser grammar) (string-append path *c-source-name*)))


(define (c-comment lines)
  (comment-bookend "/*" " *" " */" lines))


(define (c-header-comment)
  (if *file-header*
      (c-comment *file-header*)
      (c-comment *default-header*)))


(define (gen-header grammar)
  (let ((non-terms (get-non-terms grammar))
        (parser-name (if *name-prefix*
                         (string-append (camel-case-upper *name-prefix*) "parser")
                         "parser")))
    (format "~a
#ifndef ~a_H_
#define ~a_H_

#include \"waxeye.h\"

enum ~a {
~a
};

#ifndef ~a_C_

extern const char *~a_strings[];
extern struct parser_t* ~a_new();

#endif /* ~a_C_ */
#endif /* ~a_H_ */
"
            (c-header-comment)
            (string->upper *c-parser-name*)
            (string->upper *c-parser-name*)
            *c-type-name*
            (indent
             (string-append
              (ind)
              (string->upper (car non-terms))
              (string-concat
               (map (lambda (a)
                      (string-append ",\n" (ind) (string->upper a)))
                    (cdr non-terms)))))
            (string->upper *c-parser-name*)
            *c-type-name*
            *c-parser-name*
            (string->upper *c-parser-name*)
            (string->upper *c-parser-name*))))


(define (gen-parser grammar)
  (let ((automata (make-automata grammar))
        (non-terms (get-non-terms grammar)))
    (format "~a
#define ~a_C_
#include \"~a\"

const char *~a_strings[] = {
~a
};

struct parser_t* ~a_new() {
~a
}
"
            (c-header-comment)
            (string->upper *c-parser-name*)
            *c-header-name*
            *c-type-name*
            (indent
             (string-append
              (ind)
              "\"" (string->upper (car non-terms)) "\""
              (string-concat
               (map (lambda (a)
                      (string-append ",\n" (ind) "\"" (string->upper a) "\""))
                    (cdr non-terms)))))
            *c-parser-name*
            (indent
             (format "~aconst size_t start = ~a;
~aconst bool eof_check = ~a;
~asize_t num_edges;
~asize_t num_states;
~aconst size_t num_automata = ~a;
~astruct edge_t *edges;
~astruct state_t *states;
~astruct fa_t *automata = calloc(num_automata, sizeof(struct fa_t));
~aassert(automata != NULL);

~a~areturn parser_new(start, automata, num_automata, eof_check);"
                     (ind)
                     (number->string *start-index*)
                     (ind)
                     (bool->s *eof-check*)
                     (ind) (ind) (ind)
                     (number->string (vector-length automata))
                     (ind) (ind) (ind) (ind)
                     (mapi->s gen-fa (vector->list automata))
                     (ind))))))


(define (mapi->s fn l)
  (string-concat
   (let ((i -1))
     (map (lambda (a)
            (set! i (+ i 1))
            (fn i a))
          l))))


(define (gen-mode a)
  (let ((type (fa-type a)))
    (cond
     ((equal? type '&) "POS")
     ((equal? type '!) "NEG")
     (else
      (case (fa-mode a)
        ((voidArrow) "VOID")
        ((pruneArrow) "PRUNE")
        ((leftArrow) "LEFT"))))))


(define (gen-fa i a)
  (format "~anum_states = ~a;
~astates = calloc(num_states, sizeof(struct state_t));
~aassert(states != NULL);
~a~aautomata[~a] = fa_new(MODE_~a, ~a, states, num_states);\n\n"
          (ind)
          (vector-length (fa-states a))
          (ind) (ind)
          (mapi->s gen-state (vector->list (fa-states a)))
          (ind)
          i
          (gen-mode a)
          (let ((type (fa-type a)))
            (if (or (equal? type '&) (equal? type '&))
                0
                (string->upper (symbol->string type))))))


(define (gen-state i s)
  (format "~anum_edges = ~a;
~aedges = calloc(num_edges, sizeof(struct edge_t));
~aassert(edges != NULL);
~a~astates[~a] = state_new(edges, num_edges, ~a);\n"
          (ind)
          (length (state-edges s))
          (ind) (ind)
          (mapi->s gen-edge (state-edges s))
          (ind)
          i
          (bool->s (state-match s))))


(define (gen-edge i e)
  (format "~aedges[~a] = edge_new(new ~a, ~a, ~a);\n"
          (ind)
          i
          (gen-trans (edge-t e))
          (edge-s e)
          (bool->s (edge-v e))))


(define (gen-trans t)
  (cond
   ((equal? t 'wild) (gen-wild-card-trans))
   ((integer? t) (gen-automaton-trans t))
   ((char? t) (gen-char-trans t))
   ((pair? t) (gen-char-class-trans t))))


(define (gen-automaton-trans t)
  (format "AutomatonTransition<>(~a)" t))


(define (gen-char-trans t)
  (format "CharTransition<>(new char[]{~a}, new char[]{}, new char[]{})" (gen-char t)))


(define (gen-char-class-trans t)
  (let* ((single (filter char? t))
         (ranges (filter pair? t))
         (min (map car ranges))
         (max (map cdr ranges)))
    (format "CharTransition<>(~a, ~a, ~a)"
            (gen-char-list single)
            (gen-char-list min)
            (gen-char-list max))))


(define (gen-char-list l)
  (format "new char[]{~a}"
          (if (null? l)
              ""
              (string-append
               (gen-char (car l))
               (string-concat (map (lambda (a)
                                     (string-append ", " (gen-char a)))
                                   (cdr l)))))))


(define (gen-char t)
  (format "'~a~a'"
          (if (escape-for-java-char? t) "\\" "")
          (cond
           ((equal? t #\linefeed) "\\n")
           ((equal? t #\tab) "\\t")
           ((equal? t #\return) "\\r")
           (else t))))


(define (gen-wild-card-trans)
  (format "WildCardTransition<>()"))


)
