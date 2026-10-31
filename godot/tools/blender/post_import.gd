@tool
extends EditorScenePostImport
## prototype

func _post_import(scene: Node) -> Object:
	scene.set_meta("qt_post_import", get_source_file().get_file())
	print("POST_IMPORT ran for ", get_source_file())
	return scene
