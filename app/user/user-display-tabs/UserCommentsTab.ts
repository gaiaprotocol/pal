import { PostList } from "@common-module/social";
import PalPost from "../../database-interface/PalPost.js";
import PalPostInteractions from "../../post/PalPostInteractions.js";
import PalPostService from "../../post/PalPostService.js";
import PostLoadingAnimation from "../../post/PostLoadingAnimation.js";
import PalSignedUserManager from "../PalSignedUserManager.js";

export default class UserCommentsTab extends PostList<PalPost> {
  constructor(private userId: string) {
    super(
      ".user-comments-tab",
      PalPostService,
      {
        storeName: userId === PalSignedUserManager.user?.user_id
          ? "signed-user-comments"
          : undefined,
        signedUserId: PalSignedUserManager.user?.user_id,
        emptyMessage: "This user has not commented anything yet.",
      },
      PalPostInteractions,
      new PostLoadingAnimation(),
    );
  }

  protected async fetchPosts(): Promise<
    {
      fetchedPosts: { posts: PalPost[]; mainPostId: number }[];
      repostedPostIds: number[];
      likedPostIds: number[];
    }
  > {
    const result = await PalPostService.fetchUserCommentPosts(
      this.userId,
      this.lastPostId,
    );
    return {
      fetchedPosts: result.posts.map((p) => ({
        posts: [p],
        mainPostId: p.id,
      })),
      repostedPostIds: result.repostedPostIds,
      likedPostIds: result.likedPostIds,
    };
  }
}
