      ******************************************************************
      * ACCTREC - Account Master Record Layout
      * Enterprise Standard Copybook
      * System: Core Banking - VSAM KSDS
      ******************************************************************
       01 ACCT-RECORD.
           05 ACCT-NUMBER         PIC X(10).
           05 ACCT-TYPE           PIC X(02).
           05 ACCT-BALANCE        PIC S9(13)V99 COMP-3.
           05 ACCT-STATUS         PIC X(01).
           05 ACCT-LAST-UPDATED   PIC X(10).
           05 ACCT-CUSTOMER-ID    PIC X(08).
           05 FILLER              PIC X(20).
