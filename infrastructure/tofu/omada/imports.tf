import {
  for_each = var.omada_enable_management && var.adoption_mode ? { lan = local.export.network } : {}

  to = omada_network.lan[0]
  id = "${local.export.site.name}/${each.value.id}"
}

import {
  for_each = var.omada_enable_management && var.adoption_mode ? local.reservations : {}

  to = omada_dhcp_reservation.reservation[each.key]
  id = "${local.export.site.name}/${upper(replace(each.value.mac, ":", "-"))}"
}
