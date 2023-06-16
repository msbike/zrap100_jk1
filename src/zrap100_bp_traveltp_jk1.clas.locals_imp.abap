CLASS lhc_travel DEFINITION INHERITING FROM cl_abap_behavior_handler.
  PRIVATE SECTION.

    CONSTANTS:
      BEGIN OF travel_status,
        open     TYPE c LENGTH 1 VALUE 'O', "Open
        accepted TYPE c LENGTH 1 VALUE 'A', "Accepted
        rejected TYPE c LENGTH 1 VALUE 'X', "Rejected
      END OF travel_status.

    METHODS:
      get_global_authorizations FOR GLOBAL AUTHORIZATION
        IMPORTING
        REQUEST requested_authorizations FOR Travel
        RESULT result,
      earlynumbering_create FOR NUMBERING
        IMPORTING entities FOR CREATE Travel,
      setStatusToOpen FOR DETERMINE ON MODIFY
        IMPORTING keys FOR Travel~setStatusToOpen,
      validateCustomer FOR VALIDATE ON SAVE
        IMPORTING keys FOR Travel~validateCustomer.

    METHODS validateDates FOR VALIDATE ON SAVE
      IMPORTING keys FOR Travel~validateDates.
ENDCLASS.

CLASS lhc_travel IMPLEMENTATION.
  METHOD get_global_authorizations.
  ENDMETHOD.
  METHOD earlynumbering_create.

    DATA use_number_range TYPE abap_bool VALUE abap_true.
    DATA travel_id_max    TYPE /dmo/travel_id.
    DATA textid LIKE if_t100_message=>t100key.

    LOOP AT entities ASSIGNING FIELD-SYMBOL(<entity>) WHERE TravelID IS NOT INITIAL.
      APPEND CORRESPONDING #( <entity> ) TO mapped-travel.
    ENDLOOP.

    DATA(entities_wo_travelid) = entities.

    "Remove the entries with an existing Travel ID
    DELETE entities_wo_travelid WHERE TravelID IS NOT INITIAL.

    IF use_number_range = abap_true.

      "Get numbers
      TRY.

          cl_numberrange_runtime=>number_get(
            EXPORTING
              nr_range_nr       = '01'
              object            = '/DMO/TRV_M'
              quantity          = CONV #( lines( entities_wo_travelid ) )
            IMPORTING
              number            = DATA(number_range_key)
              returncode        = DATA(number_range_return_code)
              returned_quantity = DATA(number_range_returned_quantity)
          ).

        CATCH cx_number_ranges INTO DATA(lx_number_ranges).

          LOOP AT entities_wo_travelid ASSIGNING <entity>.

            APPEND VALUE #(
                %cid        = <entity>-%cid
                %key        = <entity>-%key
                %is_draft   = <entity>-%is_draft
                %msg        = lx_number_ranges ) TO reported-travel.

            APPEND VALUE #(
                %cid        = <entity>-%cid
                %key        = <entity>-%key
                %is_draft   = <entity>-%is_draft ) TO failed-travel.

          ENDLOOP.

      ENDTRY.

      "determine the first free travel ID from the number range
      travel_id_max = number_range_key - number_range_returned_quantity.

    ELSE.
      "determine the first free travel ID without number range
      "Get max travel ID from active table
      SELECT SINGLE FROM zrap100_atravjk1 FIELDS MAX( travel_id ) AS travelID INTO @travel_id_max.
      "Get max travel ID from draft table
      SELECT SINGLE FROM zrap100_dtravjk1 FIELDS MAX( travelid ) INTO @DATA(max_travelid_draft).
      IF max_travelid_draft > travel_id_max.
        travel_id_max = max_travelid_draft.
      ENDIF.

    ENDIF.

    "Set Travel ID for new instances w/o ID
    LOOP AT entities_wo_travelid ASSIGNING <entity>.
      travel_id_max += 1.
      <entity>-TravelID = travel_id_max.

      APPEND VALUE #( %cid      = <entity>-%cid
                      %key      = <entity>-%key
                      %is_draft = <entity>-%is_draft
                    ) TO mapped-travel.
    ENDLOOP.

  ENDMETHOD.

  METHOD setStatusToOpen.

    "Read travel instances of the transfered keys
    READ ENTITIES OF zrap100_r_traveltp_jk1 IN LOCAL MODE
        ENTITY Travel
            FIELDS (  OverallStatus )
            WITH CORRESPONDING #( keys )
         RESULT DATA(travels)
         FAILED DATA(read_failed).

    DELETE travels WHERE OverallStatus IS NOT INITIAL.

    IF travels IS NOT INITIAL.

      MODIFY ENTITIES OF zrap100_r_traveltp_jk1 IN LOCAL MODE
          ENTITY travel
              UPDATE FIELDS ( OverallStatus )
              WITH VALUE #( FOR travel IN travels ( %tky              = travel-%tky
                                                    OverallStatus     = travel_status-open ) )
      REPORTED DATA(update_reported).

      reported = CORRESPONDING #( DEEP update_reported ).

    ENDIF.

  ENDMETHOD.

  METHOD validateCustomer.

    READ ENTITIES OF zrap100_r_traveltp_jk1 IN LOCAL MODE
        ENTITY Travel
        FIELDS ( CustomerID )
        WITH CORRESPONDING #( keys )
        RESULT DATA(travels).

    DATA customers TYPE SORTED TABLE OF /dmo/customer WITH UNIQUE KEY customer_id.

    "optimization of DB select: extract distinct non-initial customer IDs
    customers = CORRESPONDING #( travels DISCARDING DUPLICATES MAPPING customer_id = customerID EXCEPT * ).
    DELETE customers WHERE customer_id IS INITIAL.
    IF customers IS NOT INITIAL.

      "check if customer ID exists
      SELECT FROM /dmo/customer FIELDS customer_id
                                FOR ALL ENTRIES IN @customers
                                WHERE customer_id = @customers-customer_id
        INTO TABLE @DATA(valid_customers).

    ENDIF.

    "raise msg for non existing and initial customer id
    LOOP AT travels INTO DATA(travel).

      APPEND VALUE #(  %tky                 = travel-%tky
                       %state_area          = 'VALIDATE_CUSTOMER'
                     ) TO reported-travel.

      IF travel-CustomerID IS  INITIAL.
        APPEND VALUE #( %tky = travel-%tky ) TO failed-travel.

        APPEND VALUE #( %tky                = travel-%tky
                        %state_area         = 'VALIDATE_CUSTOMER'
                        %msg                = NEW /dmo/cm_flight_messages(
                                                                textid   = /dmo/cm_flight_messages=>enter_customer_id
                                                                severity = if_abap_behv_message=>severity-error )
                        %element-CustomerID = if_abap_behv=>mk-on
                      ) TO reported-travel.

      ELSEIF travel-CustomerID IS NOT INITIAL AND NOT line_exists( valid_customers[ customer_id = travel-CustomerID ] ).
        APPEND VALUE #(  %tky = travel-%tky ) TO failed-travel.

        APPEND VALUE #(  %tky                = travel-%tky
                         %state_area         = 'VALIDATE_CUSTOMER'
                         %msg                = NEW /dmo/cm_flight_messages(
                                                                customer_id = travel-customerid
                                                                textid      = /dmo/cm_flight_messages=>customer_unkown
                                                                severity    = if_abap_behv_message=>severity-error )
                         %element-CustomerID = if_abap_behv=>mk-on
                      ) TO reported-travel.
      ENDIF.

    ENDLOOP.


  ENDMETHOD.

  METHOD validateDates.
  ENDMETHOD.

ENDCLASS.
