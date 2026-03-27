from langgraph.graph import END, StateGraph

from state import State
from nodes import merge_content, decide_images, generate_and_place_images

# build reducer subgraph
def build_reducer_subgraph():

    reducer_graph = StateGraph(State)

    reducer_graph.add_node("merge_content", merge_content)
    reducer_graph.add_node("decide_images", decide_images)
    reducer_graph.add_node("generate_and_place_images", generate_and_place_images)

    reducer_graph.set_entry_point("merge_content")
    reducer_graph.add_edge("merge_content", "decide_images")
    reducer_graph.add_edge("decide_images", "generate_and_place_images")
    reducer_graph.add_edge("generate_and_place_images", END)

    reducer_subgraph = reducer_graph.compile()

    return reducer_subgraph

