// Explicit controller registry. esbuild bundles everything imported here —
// when adding a controller, import and register it below (the old importmap
// eagerLoadControllersFrom auto-discovery is gone).
import { application } from "./application"

import BackController from "./back_controller"
import CountdownController from "./countdown_controller"
import DismissableController from "./dismissable_controller"
import EmojiPickerController from "./emoji_picker_controller"
import HelloController from "./hello_controller"
import HighlightMeController from "./highlight_me_controller"
import InfiniteScrollController from "./infinite_scroll_controller"
import PreviewSheetController from "./preview_sheet_controller"
import QtyStepperController from "./qty_stepper_controller"
import ScheduleFilterController from "./schedule_filter_controller"
import ScoreFormController from "./score_form_controller"
import SettleSelectController from "./settle_select_controller"
import StakePopupController from "./stake_popup_controller"
import VotePanelController from "./vote_panel_controller"

application.register("back", BackController)
application.register("countdown", CountdownController)
application.register("dismissable", DismissableController)
application.register("emoji-picker", EmojiPickerController)
application.register("hello", HelloController)
application.register("highlight-me", HighlightMeController)
application.register("infinite-scroll", InfiniteScrollController)
application.register("preview-sheet", PreviewSheetController)
application.register("qty-stepper", QtyStepperController)
application.register("schedule-filter", ScheduleFilterController)
application.register("score-form", ScoreFormController)
application.register("settle-select", SettleSelectController)
application.register("stake-popup", StakePopupController)
application.register("vote-panel", VotePanelController)
