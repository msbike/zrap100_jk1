CLASS lhc_travel DEFINITION INHERITING FROM cl_abap_behavior_handler.
  PRIVATE SECTION.
    METHODS:
      get_global_authorizations FOR GLOBAL AUTHORIZATION
        IMPORTING
        REQUEST requested_authorizations FOR Travel
        RESULT result,
      earlynumbering_create FOR NUMBERING
        IMPORTING entities FOR CREATE Travel.
ENDCLASS.

CLASS lhc_travel IMPLEMENTATION.
  METHOD get_global_authorizations.
  ENDMETHOD.
  METHOD earlynumbering_create.

    DATA use_number_range TYPE abap_bool VALUE abap_true.
    DATA travel_id_max    TYPE /dmo/travel_id.

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
                %is_draft   = <entity>-%is_draft ) TO reported-travel.

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

ENDCLASS.
