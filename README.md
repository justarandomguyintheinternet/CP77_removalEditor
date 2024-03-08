# Installation
- Download and install this mod
- Download and install [RedHotTools](https://github.com/psiberx/cp2077-red-hot-tools), with all its dependencies

# Usage
- Open the CET Overlay and find the `Removal Editor` window
## Important Note
- Removal Editor only creates a ready to use `.xl` file in it's `data` folder.
- This means that it in itself does not handle any removing, for that you must place the `.xl` file in the the games `mod` folder, and have [ArchiveXL](https://github.com/psiberx/cp2077-archive-xl) installed
- **However when sending a node to Removal Editor from RHT, the node visibility (For those which support it, e.g. mesh nodes) will get toggled off, for easier previewing. This is only temporary, and will revert as soon as the node is un and re-streamed.**
## Presets Tab
Here you can create a new preset by entering a name in the `Name...` field and hitting `Create`
- Each preset is a collection of removed objects. Use this to organise things.
- Expanding a preset's header and press will reveal more information, and a `Edit` and `Delete` button
- Use the `Edit` button to load a preset into the editor (`Edit` tab)
## Edit Tab
- Here you can see what nodes the preset removes
- You can add a node to an opened preset directly, by identifying the node in RHT, then pressing the `Send to Removal Editor` button in RHT
- By changing the staging mode to `Add with confirmation`, each node sent to Removal Editor staged, allowing you to immediately add a Note to the node, before hitting the `Add  Staged Node` button
- Bellow you will see a list of all the nodes in the preset
- You can expand each node's header to either add a note, or remove the node from the preset
## Finding Nodes
- For finding collision nodes with RHT, use the `Inspect` tab, and look directly at the collision
- For any non-targetable node (Not entities or collisions), use the `Scan` tab of RHT
## Node information
- Collision Nodes: Collision Nodes are made up of multiple `Actors`, each actor can be some shape, like a box, sphere / pill, and more complex shapes. Removal Editor removes all the actors of a collision node by default. This can sometimes lead to more being removed than anticipated. You can manually un-remove actors by editing the `actorDeletions` field of the node, in the generated `.xl` file
- Occluder nodes: Currently RHT does not pick up on instanced mesh occluder nodes, so often it is impossible to remove the ones you want