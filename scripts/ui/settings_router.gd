class_name SettingsRouter
extends RefCounted
## Which settings page the button opens.
##
## Nineteen pages, one line each. It lived in `main.gd` and it belongs beside
## the pages it names — but what actually moved it was the size budget: adding
## the AI page put `main.gd` two lines past its ceiling and the build stopped.
##
## Two lines is exactly the amount nobody argues with, and a hundred and
## seventy builds of nobody arguing is how a file reaches three thousand
## lines. So it was paid for rather than waved through, and the router is
## thirty-four lines that are now somewhere sensible.

## The settings button is a stack of pages rather than a pile of dialogs:
## one panel, one place on screen, and Back always means the same thing.
static func open_settings_page(p: MainRoom, page: String) -> void:
	p._settings_page = page
	p._close_panel()
	var built: PanelContainer = null
	if page == "new":
		built = SettingsPanels.new_project(p, "drawing")
	elif page == "comic":
		built = SettingsPanels.new_project(p, "comic")
	elif page == "animation_new":
		built = SettingsPanels.animation_project_start(p)
	elif page == "new_animation_ivory":
		built = SettingsPanels.new_animation_ivory_project(p)
	elif page == "language":
		built = SettingsPanels.language(p)
	elif page == "frame":
		built = SettingsPanels.frame_colour(p)
	elif page == "export":
		built = SettingsPanels.export_page(p)
	elif page == "share":
		built = SettingsPanels.share_page(p)
	elif page == "animation":
		built = SettingsPanels.animation_page(p)
	elif page == "mp4":
		built = ExportPanel.page(p, func() -> void:
			open_settings_page(p, "animation"))
	elif page == "make":
		built = SettingsPanels.make_menu(p)
	elif page == "storage":
		built = SettingsPanels.storage_page(p)
	elif page == "transfer":
		built = SettingsPanels.transfer_layers(p)
	elif page == "transfer_to":
		built = SettingsPanels.transfer_target(p)
	elif page == "transfer_how":
		built = SettingsPanels.transfer_mode(p)
	elif page == "information":
		built = SettingsPanels.information(p)
	else:
		built = SettingsPanels.menu(p)
	p._mount(built, "settings")
