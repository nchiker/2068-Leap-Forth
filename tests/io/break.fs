\ BREAK? is false with no key held and leaves KEY?'s latched key alone
BREAK? .                               \ expect: 0
\ keys: X
1 {KBD_KEYHIT} C! 88 {KBD_LASTK} C! BREAK? DROP KEY? . KEY .                \ expect: -1 88
