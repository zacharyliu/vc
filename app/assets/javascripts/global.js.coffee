jQuery ->
  $('#toggle_active').on 'ajax:success', (ev) ->
    $('#user_drop').toggleClass 'inactive_user'
    if $('#toggle_active').text() is 'Go Active'
      $('#toggle_active').text 'Go Inactive'
    else
      $('#toggle_active').text 'Go Active'
