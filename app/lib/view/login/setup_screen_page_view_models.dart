import 'package:flutter/material.dart';
import 'package:introduction_screen/introduction_screen.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:sph_plan/applets/definitions.dart';
import 'package:sph_plan/shared/account_types.dart';
import 'package:sph_plan/view/settings/subsettings/notifications.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../../core/sph/sph.dart';

List<PageViewModel> setupScreenPageViewModels(BuildContext context) => [
      //todo @codespoof
      if (sph!.session.accountType != AccountType.student)
        PageViewModel(
            image: SvgPicture.asset("assets/undraw/undraw_profile_re_4a55.svg",
                height: 175.0),
            title: AppLocalizations.of(context)!.setupNonStudentTitle,
            body: AppLocalizations.of(context)!.setupNonStudent),
      if (AppDefinitions.isAppletSupported(sph!.session.accountType, 'vertretungsplan.php')) ...[
        PageViewModel(
            image: SvgPicture.asset(
                "assets/undraw/undraw_new_notifications_re_xpcv.svg",
                height: 175.0),
            title: AppLocalizations.of(context)!.setupPushNotificationsTitle,
            body: AppLocalizations.of(context)!.setupPushNotifications),
        PageViewModel(
            image: SvgPicture.asset(
                "assets/undraw/undraw_active_options_re_8rj3.svg",
                height: 175.0),
            title: AppLocalizations.of(context)!.setupPushNotificationsTitle,
            bodyWidget: const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [NotificationElements()],
            )),
      ],
      PageViewModel(
          image: SvgPicture.asset("assets/undraw/undraw_add_color_re_buro.svg",
              height: 175.0),
          title: AppLocalizations.of(context)!.appearance,
          bodyWidget: const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [],
          )),
      PageViewModel(
          image: SvgPicture.asset("assets/undraw/undraw_welcome_re_h3d9.svg",
              height: 175.0),
          title: AppLocalizations.of(context)!.setupReadyTitle,
          body: AppLocalizations.of(context)!.setupReady),
    ];
